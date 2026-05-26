//! Forward request translation: client format → upstream format.
//!
//! Ten-step pipeline, each step a pure function. Applied in fixed order:
//! 1. Validate all tools have a rule
//! 2. Drop tools + their tool_use/tool_result blocks
//! 3. Rename tools (name + input_schema from registry)
//! 4. Rename properties in tool_use.input values
//! 5. Detect + replace system prompt
//! 6. Text replacements on text blocks
//! 7. Inject billing block (with SHA256 fingerprint)
//! 8. Inject metadata (device_id + session_id)
//! 9. Strip trailing assistant prefill messages
//! 10. Apply unknown-field rules (strip / keep / rename, warn on unhandled)

use sha2::{Digest, Sha256};

use crate::wire::content::ContentBlock;
use crate::wire::content::CacheControl;
use crate::wire::request::{
    MessageContent, Metadata, MessagesRequest, Role, SystemBlock, SystemPrompt, Thinking,
    ToolChoice,
};

use super::{PropertyRename, RuleError, RuleSet, UnmappedPolicy};

/// Apply all forward translation rules to a request.
pub fn apply_request_rules(
    req: MessagesRequest,
    rules: &RuleSet,
    session_id: &str,
    device_id: &str,
) -> Result<MessagesRequest, RuleError> {
    apply_request_rules_with_changes(req, rules, session_id, device_id).map(|(r, _)| r)
}

/// Apply all forward translation rules to a request, also returning a
/// human-readable description of every transformation performed. Used
/// by the session log to populate `request_changes`.
pub fn apply_request_rules_with_changes(
    mut req: MessagesRequest,
    rules: &RuleSet,
    session_id: &str,
    device_id: &str,
) -> Result<(MessagesRequest, Vec<String>), RuleError> {
    let mut changes: Vec<String> = Vec::new();

    // Step 1: Validate all tools have a rule
    validate_tools(&req, rules)?;

    // Step 2: Drop tools
    drop_tools(&mut req, rules, &mut changes);

    // Step 3: Rename tools
    rename_tools(&mut req, rules, &mut changes);

    // Step 4: Rename properties in tool_use.input
    rename_properties(&mut req, rules, &mut changes)?;

    // Step 5: System prompt detection + replacement
    replace_system_prompt(&mut req, rules, &mut changes);

    // Step 6: Text replacements (system prompt only)
    apply_text_replacements(&mut req, rules, &mut changes);

    // Step 6b: Append enhancement text to system prompt
    append_to_system_prompt(&mut req, rules, &mut changes);

    // Step 6c: Append env-var-driven text (e.g. jail/sandbox context)
    append_env_system_prompt(&mut req, &mut changes);

    // Step 7: Billing block injection (with SHA256 fingerprint)
    inject_billing_block(&mut req, rules, &mut changes);

    // Step 8: Inject metadata (device_id + session_id)
    inject_metadata(&mut req, rules, session_id, device_id, &mut changes);

    // Step 9: Strip trailing assistant prefill
    strip_trailing_prefill(&mut req, &mut changes);

    // Step 10: Apply unknown-field rules. Anything unhandled still warns
    // so we can add explicit rules for it (these fields are fingerprint
    // signals -- real Claude Code only sends documented Anthropic fields).
    apply_unknown_field_rules(&mut req, rules, &mut changes);

    // Step 11: Inject thinking:{type:"adaptive"} when absent
    inject_thinking(&mut req, rules, &mut changes);

    // Step 12: Inject context_management when absent
    inject_context_management(&mut req, rules, &mut changes);

    // Step 13: Strip tool_choice:{type:"auto"} (real CC omits it)
    strip_tool_choice_auto(&mut req, rules, &mut changes);

    // Step 14: Override max_tokens
    override_max_tokens(&mut req, rules, &mut changes);

    Ok((req, changes))
}

fn apply_unknown_field_rules(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) {
    if req.extra.is_empty() {
        return;
    }

    let names: Vec<String> = req.extra.keys().cloned().collect();
    let mut unhandled: Vec<&str> = Vec::new();

    for name in &names {
        match rules.unknown_field_rules.get(name) {
            Some(super::UnknownFieldRule::Strip) => {
                req.extra.remove(name);
                changes.push(format!("stripped unknown field: {name}"));
            }
            Some(super::UnknownFieldRule::Keep) => {
                // leave it
            }
            Some(super::UnknownFieldRule::Rename(target)) => {
                if let Some(value) = req.extra.remove(name) {
                    req.extra.insert(target.clone(), value);
                    changes.push(format!("renamed unknown field: {name} → {target}"));
                }
            }
            None => {
                unhandled.push(name.as_str());
            }
        }
    }

    if !unhandled.is_empty() {
        tracing::warn!(
            fields = ?unhandled,
            "forwarding unknown request fields to upstream (add an unknown_fields rule to handle them)"
        );
        for f in &unhandled {
            changes.push(format!("forwarded unknown field (no rule): {f}"));
        }
    }
}

/// Step 1: Validate that all tools in the request have a mapping rule.
fn validate_tools(req: &MessagesRequest, rules: &RuleSet) -> Result<(), RuleError> {
    if rules.unmapped_policy != UnmappedPolicy::Error {
        return Ok(());
    }

    for tool in &req.tools {
        if !rules.tool_renames.contains_key(&tool.name)
            && !rules.tool_drops.contains(&tool.name)
        {
            return Err(RuleError::UnmappedTool(tool.name.clone()));
        }
    }

    Ok(())
}

/// Step 2: Remove dropped tools from the tools list and their
/// tool_use/tool_result blocks from message history.
fn drop_tools(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    if rules.tool_drops.is_empty() {
        return;
    }

    // Collect IDs of tool_use blocks that belong to dropped tools
    let mut dropped_ids: std::collections::HashSet<String> = std::collections::HashSet::new();
    for msg in &req.messages {
        if let MessageContent::Blocks(blocks) = &msg.content {
            for block in blocks {
                if let ContentBlock::ToolUse { id, name, .. } = block {
                    if rules.tool_drops.contains(name) {
                        dropped_ids.insert(id.clone());
                    }
                }
            }
        }
    }

    // Remove tool definitions
    let before = req.tools.len();
    req.tools.retain(|t| !rules.tool_drops.contains(&t.name));
    let dropped_def_count = before - req.tools.len();

    // Remove tool_use and tool_result blocks for dropped tools
    for msg in &mut req.messages {
        if let MessageContent::Blocks(blocks) = &mut msg.content {
            blocks.retain(|block| match block {
                ContentBlock::ToolUse { name, .. } => !rules.tool_drops.contains(name),
                ContentBlock::ToolResult { tool_use_id, .. } => {
                    !dropped_ids.contains(tool_use_id)
                }
                _ => true,
            });
        }
    }

    // Remove messages that became empty after dropping blocks
    req.messages.retain(|msg| match &msg.content {
        MessageContent::Blocks(blocks) => !blocks.is_empty(),
        MessageContent::String(s) => !s.is_empty(),
    });

    if dropped_def_count > 0 {
        changes.push(format!(
            "dropped {dropped_def_count} tool definition(s): {}",
            rules
                .tool_drops
                .iter()
                .cloned()
                .collect::<Vec<_>>()
                .join(", ")
        ));
    }
}

/// Step 3: Rename tools — substitute name, description, and optionally input_schema.
///
/// Description is always replaced when the registry provides one.
/// Schema replacement is opt-in: only when the registry entry defines
/// an `input_schema` is the client's schema overridden. When not
/// overriding, the client's original schema is preserved intact —
/// this avoids stripping nested structures (e.g., `items` in array
/// schemas for tools like TodoWrite and AskUser).
///
/// When overriding, the client's `required` and `additionalProperties`
/// are preserved as fallback if the registry schema doesn't specify them.
fn rename_tools(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    // Rename tool definitions
    for tool in &mut req.tools {
        if let Some(resolved) = rules.tool_renames.get(&tool.name) {
            let old_name = tool.name.clone();
            tool.name = resolved.canonical_name.clone();

            if old_name != resolved.canonical_name {
                changes.push(format!(
                    "tool rename: {old_name} → {}",
                    resolved.canonical_name
                ));
            }

            // Always replace description if the registry provides one
            if let Some(ref desc) = resolved.description {
                tool.description = Some(desc.clone());
            }

            // Only replace schema if the registry explicitly defines an override
            if let Some(ref schema_override) = resolved.schema_override {
                tracing::debug!(
                    tool = %old_name,
                    canonical = %resolved.canonical_name,
                    "replacing client schema with registry override"
                );
                // Extract client's required/additionalProperties for merge fallback
                let client_required = tool.input_schema.get("required").cloned();
                let client_additional_props =
                    tool.input_schema.get("additionalProperties").cloned();

                tool.input_schema = schema_override.to_value();

                // Merge: prefer registry values, fall back to client values
                if let serde_json::Value::Object(ref mut map) = tool.input_schema {
                    if !map.contains_key("required") {
                        if let Some(v) = client_required {
                            map.insert("required".into(), v);
                        }
                    }
                    if !map.contains_key("additionalProperties") {
                        if let Some(v) = client_additional_props {
                            map.insert("additionalProperties".into(), v);
                        }
                    }
                }
                changes.push(format!(
                    "tool schema override: {}",
                    resolved.canonical_name
                ));
            } else {
                tracing::trace!(
                    tool = %old_name,
                    canonical = %resolved.canonical_name,
                    "preserving client schema (no registry override)"
                );
            }
        }
    }

    // Rename tool_use references in message history
    for msg in &mut req.messages {
        if let MessageContent::Blocks(blocks) = &mut msg.content {
            for block in blocks {
                if let ContentBlock::ToolUse { name, .. } = block {
                    if let Some(resolved) = rules.tool_renames.get(name.as_str()) {
                        *name = resolved.canonical_name.clone();
                    }
                }
            }
        }
    }
}

/// Step 4: Walk all tool_use.input values and rename properties.
fn rename_properties(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) -> Result<(), RuleError> {
    if rules.property_renames.is_empty() {
        return Ok(());
    }

    for msg in &mut req.messages {
        if let MessageContent::Blocks(blocks) = &mut msg.content {
            for block in blocks {
                if let ContentBlock::ToolUse { input, .. } = block {
                    rename_properties_in_value(input, &rules.property_renames);
                }
            }
        }
    }

    let renames: Vec<String> = rules
        .property_renames
        .iter()
        .map(|r| format!("{} → {}", r.from, r.to))
        .collect();
    if !renames.is_empty() {
        changes.push(format!("property renames applied: {}", renames.join(", ")));
    }

    Ok(())
}

/// Recursively rename properties in a JSON value.
pub(crate) fn rename_properties_in_value(
    value: &mut serde_json::Value,
    renames: &[PropertyRename],
) {
    match value {
        serde_json::Value::Object(map) => {
            // Collect renames to apply (can't mutate while iterating)
            let keys_to_rename: Vec<(String, String)> = renames
                .iter()
                .filter(|r| map.contains_key(&r.from))
                .map(|r| (r.from.clone(), r.to.clone()))
                .collect();

            for (from, to) in keys_to_rename {
                if let Some(val) = map.remove(&from) {
                    map.insert(to, val);
                }
            }

            // Recurse into values
            for val in map.values_mut() {
                rename_properties_in_value(val, renames);
            }
        }
        serde_json::Value::Array(arr) => {
            for val in arr {
                rename_properties_in_value(val, renames);
            }
        }
        _ => {}
    }
}

/// Step 5: Detect and replace the system prompt.
///
/// Three-tier replacement:
/// 1. **Marker**: if system text starts with `[proxy:replace=NAME]`, look up
///    NAME in the markers map and use that replacement text.
/// 2. **Detect substring**: if `detect` is set and matches, use `replace_with_file`.
/// 3. **Unconditional**: if no `detect` but `replace_with_file` is set, always replace.
///
/// After replacement, emits the CC-standard 2-block structure (identity line +
/// main prompt, each with `cache_control: {type: "ephemeral", ttl: "1h"}`).
/// The billing block is added separately in step 7.
fn replace_system_prompt(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    let system_text = match &req.system {
        Some(s) => s.text_content(),
        None => return,
    };

    // Tier 1: marker-based replacement
    if let Some(replacement) = try_marker_replacement(&system_text, rules) {
        let before_len = system_text.len();
        let after_len = replacement.len();
        req.system = Some(make_cc_system_blocks(&replacement));
        changes.push(format!(
            "system prompt: marker-replaced ({before_len} → {after_len} chars)"
        ));
        return;
    }

    // Tier 2/3: detect-based or unconditional replacement
    let replacement = match &rules.system_prompt_replacement {
        Some(r) => r,
        None => return,
    };

    if let Some(ref detect) = rules.system_prompt_detect {
        if !system_text.contains(detect.as_str()) {
            return;
        }
    }

    let before_len = system_text.len();
    let after_len = replacement.len();
    req.system = Some(make_cc_system_blocks(replacement));
    changes.push(format!(
        "system prompt: replaced ({before_len} → {after_len} chars)"
    ));
}

/// Try to find a `[proxy:replace=NAME]` marker at the start of the system
/// text and look up the replacement in the markers map.
fn try_marker_replacement<'a>(text: &str, rules: &'a RuleSet) -> Option<&'a String> {
    let text = text.trim_start();
    if !text.starts_with("[proxy:replace=") {
        return None;
    }
    let rest = &text["[proxy:replace=".len()..];
    let end = rest.find(']')?;
    let name = &rest[..end];
    let replacement = rules.system_prompt_markers.get(name);
    if replacement.is_none() {
        tracing::warn!(
            "system prompt has marker [proxy:replace={name}] but no marker rule found — falling through to detect"
        );
    }
    replacement
}

/// Build the 2-block system prompt structure matching real CC:
///   Block 0: identity line with cache_control
///   Block 1: main prompt with cache_control
///
/// The billing block (block -1 in real CC) is prepended separately by
/// `inject_billing_block()`.
fn make_cc_system_blocks(prompt_text: &str) -> SystemPrompt {
    let cc_cache = Some(CacheControl {
        cache_type: "ephemeral".into(),
        ttl: Some("1h".into()),
    });
    SystemPrompt::Blocks(vec![
        SystemBlock::Text {
            text: "You are Claude Code, Anthropic's official CLI for Claude.\n".into(),
            cache_control: cc_cache.clone(),
        },
        SystemBlock::Text {
            text: prompt_text.to_string(),
            cache_control: cc_cache,
        },
    ])
}

/// Step 6: Apply text replacements to the system prompt only.
///
/// Message content blocks are intentionally left untouched — the proxy
/// should not mutate user or assistant text in the conversation history,
/// only the initialization prompt that it is replacing wholesale.
fn apply_text_replacements(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) {
    if rules.text_replacements.is_empty() {
        return;
    }

    let mut total_hits = 0usize;

    // Apply to system prompt only
    if let Some(SystemPrompt::Blocks(blocks)) = &mut req.system {
        for block in blocks {
            let SystemBlock::Text { text, .. } = block;
            for tr in &rules.text_replacements {
                let hits = text.matches(&tr.find).count();
                if hits > 0 {
                    *text = text.replace(&tr.find, &tr.replace);
                    total_hits += hits;
                }
            }
        }
    }

    if total_hits > 0 {
        changes.push(format!("text replacements applied: {total_hits} hit(s)"));
    }
}

/// Step 6b: Append enhancement text to the system prompt.
///
/// Adds the pre-read append text as a new system block after all other
/// system prompt transformations (replacement, text replacements) have
/// been applied. This allows injecting additional behavioral guidelines
/// without replacing the client's base prompt.
fn append_to_system_prompt(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) {
    let append_text = match &rules.system_prompt_append {
        Some(t) if !t.is_empty() => t,
        _ => return,
    };

    match &mut req.system {
        Some(SystemPrompt::Blocks(blocks)) => {
            blocks.push(SystemBlock::Text {
                text: append_text.clone(),
                cache_control: None,
            });
        }
        Some(SystemPrompt::String(s)) => {
            req.system = Some(SystemPrompt::Blocks(vec![
                SystemBlock::Text {
                    text: s.clone(),
                    cache_control: None,
                },
                SystemBlock::Text {
                    text: append_text.clone(),
                    cache_control: None,
                },
            ]));
        }
        None => {
            req.system = Some(SystemPrompt::Blocks(vec![SystemBlock::Text {
                text: append_text.clone(),
                cache_control: None,
            }]));
        }
    }

    changes.push(format!(
        "system prompt: appended {} chars",
        append_text.len()
    ));
}

/// Append extra system-prompt text supplied via the `COMPAT_PROXY_APPEND_SYSTEM`
/// environment variable.  Read once per request (cheap — the var is typically
/// only set inside jailed / sandboxed environments).
fn append_env_system_prompt(req: &mut MessagesRequest, changes: &mut Vec<String>) {
    let text = match std::env::var("COMPAT_PROXY_APPEND_SYSTEM") {
        Ok(v) if !v.is_empty() => v,
        _ => return,
    };

    match &mut req.system {
        Some(SystemPrompt::Blocks(blocks)) => {
            blocks.push(SystemBlock::Text {
                text: text.clone(),
                cache_control: None,
            });
        }
        Some(SystemPrompt::String(s)) => {
            req.system = Some(SystemPrompt::Blocks(vec![
                SystemBlock::Text {
                    text: s.clone(),
                    cache_control: None,
                },
                SystemBlock::Text {
                    text: text.clone(),
                    cache_control: None,
                },
            ]));
        }
        None => {
            req.system = Some(SystemPrompt::Blocks(vec![SystemBlock::Text {
                text: text.clone(),
                cache_control: None,
            }]));
        }
    }

    changes.push(format!(
        "system prompt: appended {} chars from env",
        text.len()
    ));
}

/// Compute the billing fingerprint hash matching real CC's computeFingerprint().
/// SHA256(salt + msg[indices[0]] + msg[indices[1]] + msg[indices[2]] + version)[:3]
fn compute_billing_fingerprint(
    first_user_text: &str,
    salt: &str,
    indices: &[usize],
    cc_version: &str,
) -> String {
    let chars: String = indices
        .iter()
        .map(|&i| {
            first_user_text
                .chars()
                .nth(i)
                .unwrap_or('0')
        })
        .collect();

    let input = format!("{salt}{chars}{cc_version}");
    let hash = Sha256::digest(input.as_bytes());
    hex::encode(&hash[..])
        .chars()
        .take(3)
        .collect()
}

/// Extract the text of the first user message for billing fingerprint.
fn extract_first_user_text(req: &MessagesRequest) -> String {
    for msg in &req.messages {
        if msg.role == Role::User {
            match &msg.content {
                MessageContent::String(s) => return s.clone(),
                MessageContent::Blocks(blocks) => {
                    for block in blocks {
                        if let ContentBlock::Text { text, .. } = block {
                            return text.clone();
                        }
                    }
                }
            }
        }
    }
    String::new()
}

/// Encode bytes as hex string (avoids pulling in the `hex` crate).
mod hex {
    pub fn encode(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }
}

/// Step 7: Inject the billing block into the system prompt.
///
/// Computes a per-request SHA256 fingerprint from the first user message
/// matching real CC's billing header format:
///   x-anthropic-billing-header: cc_version=2.1.97.<hash>; cc_entrypoint=cli; cch=00000;
fn inject_billing_block(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    if !rules.inject_billing_block {
        return;
    }

    let version = rules
        .billing_cc_version
        .as_deref()
        .unwrap_or(&rules.cc_version);

    let first_text = extract_first_user_text(req);
    let fingerprint = compute_billing_fingerprint(
        &first_text,
        &rules.billing_hash_salt,
        &rules.billing_hash_indices,
        version,
    );

    let billing_text = format!(
        "x-anthropic-billing-header: cc_version={version}.{fingerprint}; cc_entrypoint=cli; cch=00000;"
    );

    let billing_block = SystemBlock::Text {
        text: billing_text,
        cache_control: None,
    };

    match &mut req.system {
        Some(SystemPrompt::Blocks(blocks)) => {
            // Insert at the beginning (like the JS proxy does)
            blocks.insert(0, billing_block);
        }
        Some(SystemPrompt::String(s)) => {
            // Convert to blocks form
            let existing = SystemBlock::Text {
                text: std::mem::take(s),
                cache_control: None,
            };
            req.system = Some(SystemPrompt::Blocks(vec![billing_block, existing]));
        }
        None => {
            req.system = Some(SystemPrompt::Blocks(vec![billing_block]));
        }
    }

    changes.push(format!(
        "billing block injected: cc_version={version}.{fingerprint}"
    ));
}

/// Step 8: Inject metadata (device_id + session_id + account_uuid) matching real CC format.
///
/// Real CC sends: metadata.user_id = JSON.stringify({device_id, account_uuid, session_id})
fn inject_metadata(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    session_id: &str,
    device_id: &str,
    changes: &mut Vec<String>,
) {
    let mut meta_value = serde_json::json!({
        "device_id": device_id,
        "session_id": session_id,
    });

    if let Some(ref uuid) = rules.account_uuid {
        meta_value["account_uuid"] = serde_json::Value::String(uuid.clone());
    }

    req.metadata = Some(Metadata {
        user_id: Some(meta_value.to_string()),
    });

    changes.push("metadata injected: user_id".to_string());
}

/// Step 9: Strip trailing assistant messages (prefill).
///
/// Some clients send a trailing assistant message as a prefill hint.
/// The upstream API may reject these. Remove them.
fn strip_trailing_prefill(req: &mut MessagesRequest, changes: &mut Vec<String>) {
    let mut stripped = 0usize;
    while req
        .messages
        .last()
        .map_or(false, |m| m.role == Role::Assistant)
    {
        req.messages.pop();
        stripped += 1;
    }
    if stripped > 0 {
        changes.push(format!("stripped {stripped} trailing assistant prefill message(s)"));
    }
}

/// Step 11: Inject `thinking: {type: "adaptive"}` when absent.
///
/// Real CC sends this on models that support it (opus, sonnet) but NOT
/// on haiku. Only inject when the model name contains "opus" or "sonnet".
/// When thinking is active, temperature must be unset (Anthropic API requirement).
fn inject_thinking(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    if !rules.inject_thinking {
        return;
    }
    // Only inject on models that support adaptive thinking
    let model = req.model.to_lowercase();
    if !model.contains("opus") && !model.contains("sonnet") {
        return;
    }
    if req.thinking.is_none() {
        req.thinking = Some(Thinking {
            thinking_type: "adaptive".into(),
            budget_tokens: None,
        });
        changes.push("thinking injected: type=adaptive".into());
    }
    // Anthropic requires temperature=1 (or unset) when thinking is enabled.
    if req.thinking.is_some() && req.temperature.is_some() {
        req.temperature = None;
        changes.push("temperature stripped (required for thinking mode)".into());
    }
}

/// Step 12: Inject `context_management` when absent.
///
/// Real CC sends `{edits: [{keep: "all", type: "clear_thinking_20251015"}]}`
/// on models that support thinking (opus, sonnet). Skip on haiku.
fn inject_context_management(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) {
    if !rules.inject_context_management {
        return;
    }
    let model = req.model.to_lowercase();
    if !model.contains("opus") && !model.contains("sonnet") {
        return;
    }
    if !req.extra.contains_key("context_management") {
        req.extra.insert(
            "context_management".into(),
            serde_json::json!({
                "edits": [{"keep": "all", "type": "clear_thinking_20251015"}]
            }),
        );
        changes.push("context_management injected".into());
    }
}

/// Step 13: Strip `tool_choice: {type: "auto"}`.
///
/// Real CC never sends tool_choice. OpenCode sends `{type: "auto"}` on
/// every request. Strip it to match real CC's fingerprint.
fn strip_tool_choice_auto(
    req: &mut MessagesRequest,
    rules: &RuleSet,
    changes: &mut Vec<String>,
) {
    if !rules.strip_tool_choice_auto {
        return;
    }
    if let Some(ToolChoice::Auto { .. }) = &req.tool_choice {
        req.tool_choice = None;
        changes.push("stripped tool_choice: auto".into());
    }
}

/// Step 14: Override max_tokens to match real CC.
///
/// Only overrides when the current value matches OpenCode's default (32000).
/// Requests with other values (e.g. title gen's max_tokens=1) are left alone.
fn override_max_tokens(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    if let Some(target) = rules.max_tokens_override {
        // Only override OpenCode's default, not intentionally-small values
        if req.max_tokens == 32000 && req.max_tokens != target {
            let old = req.max_tokens;
            req.max_tokens = target;
            changes.push(format!("max_tokens overridden: {old} → {target}"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::{ResolvedToolRename, TextReplacement};
    use crate::wire::request::{InputSchema, Message, Tool};    fn minimal_ruleset() -> RuleSet {
        RuleSet {
            client_name: "test".into(),
            cc_version: "1.0".into(),
            system_prompt_detect: None,
            system_prompt_replacement: None,
            system_prompt_append: None,
            text_replacements: vec![],
            tool_renames: std::collections::HashMap::new(),
            tool_drops: std::collections::HashSet::new(),
            unmapped_policy: UnmappedPolicy::Passthrough,
            property_renames: vec![],
            headers: vec![],
            inject_billing_block: false,
            billing_cc_version: None,
            billing_hash_salt: "59cf53e54c78".into(),
            billing_hash_indices: vec![4, 7, 20],
            unknown_field_rules: std::collections::HashMap::new(),
            system_prompt_markers: std::collections::HashMap::new(),
            max_tokens_override: None,
            inject_thinking: false,
            inject_context_management: false,
            strip_tool_choice_auto: false,
            account_uuid: None,
        }
    }

    #[test]
    fn test_unmapped_tool_error() {
        let mut rules = minimal_ruleset();
        rules.unmapped_policy = UnmappedPolicy::Error;

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: None,
            messages: vec![],
            tools: vec![Tool {
                name: "unknown_tool".into(),
                description: None,
                input_schema: serde_json::json!({"type": "object"}),
                cache_control: None,
            }],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device");
        assert!(matches!(result, Err(RuleError::UnmappedTool(_))));
    }

    #[test]
    fn test_tool_drop() {
        let mut rules = minimal_ruleset();
        rules.tool_drops.insert("mcp_question".into());

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: None,
            messages: vec![Message {
                role: Role::User,
                content: MessageContent::Blocks(vec![
                    ContentBlock::Text {
                        text: "hello".into(),
                        cache_control: None,
                    },
                    ContentBlock::ToolUse {
                        id: "tu_1".into(),
                        name: "mcp_question".into(),
                        input: serde_json::json!({}),
                        cache_control: None,
                    },
                ]),
            }],
            tools: vec![
                Tool {
                    name: "mcp_question".into(),
                    description: None,
                    input_schema: serde_json::json!({"type": "object"}),
                    cache_control: None,
                },
                Tool {
                    name: "mcp_bash".into(),
                    description: None,
                    input_schema: serde_json::json!({"type": "object"}),
                    cache_control: None,
                },
            ],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        assert_eq!(result.tools.len(), 1);
        assert_eq!(result.tools[0].name, "mcp_bash");
        // The tool_use block for mcp_question should be gone
        if let MessageContent::Blocks(blocks) = &result.messages[0].content {
            assert_eq!(blocks.len(), 1);
            assert!(matches!(blocks[0], ContentBlock::Text { .. }));
        } else {
            panic!("expected blocks");
        }
    }

    #[test]
    fn test_tool_rename() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_bash".into(),
            ResolvedToolRename {
                canonical_name: "Bash".into(),
                description: Some("Execute a command".into()),
                schema_override: Some(InputSchema {
                    schema_type: "object".into(),
                    properties: Some(serde_json::json!({
                        "command": {"type": "string"}
                    })),
                    required: Some(vec!["command".into()]),
                    additional_properties: None,
                }),
            },
        );

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: None,
            messages: vec![Message {
                role: Role::User,
                content: MessageContent::Blocks(vec![ContentBlock::ToolUse {
                    id: "tu_1".into(),
                    name: "mcp_bash".into(),
                    input: serde_json::json!({"command": "ls"}),
                    cache_control: None,
                }]),
            }],
            tools: vec![Tool {
                name: "mcp_bash".into(),
                description: None,
                input_schema: serde_json::json!({"type": "object"}),
                cache_control: None,
            }],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        assert_eq!(result.tools[0].name, "Bash");
        if let MessageContent::Blocks(blocks) = &result.messages[0].content {
            if let ContentBlock::ToolUse { name, .. } = &blocks[0] {
                assert_eq!(name, "Bash");
            } else {
                panic!("expected tool_use");
            }
        }
    }

    #[test]
    fn test_tool_rename_preserves_client_schema_when_no_override() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_todo".into(),
            ResolvedToolRename {
                canonical_name: "TodoWrite".into(),
                description: Some("Write todos".into()),
                schema_override: None, // No schema override — client schema preserved
            },
        );

        let client_schema = InputSchema {
            schema_type: "object".into(),
            properties: Some(serde_json::json!({
                "todos": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "id": {"type": "string"},
                            "content": {"type": "string"},
                            "title": {"type": "string"}
                        },
                        "required": ["id", "content", "title"]
                    }
                }
            })),
            required: Some(vec!["todos".into()]),
            additional_properties: Some(serde_json::Value::Bool(false)),
        };

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: None,
            messages: vec![],
            tools: vec![Tool {
                name: "mcp_todo".into(),
                description: Some("Client description".into()),
                input_schema: client_schema.to_value(),
                cache_control: None,
            }],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        let tool = &result.tools[0];

        // Name and description should be replaced
        assert_eq!(tool.name, "TodoWrite");
        assert_eq!(tool.description.as_deref(), Some("Write todos"));

        // Schema should be preserved from the client (including nested items)
        let props = tool.input_schema.get("properties").unwrap();
        assert!(props["todos"]["items"]["properties"]["content"].is_object());
        assert_eq!(
            tool.input_schema.get("required"),
            Some(&serde_json::json!(["todos"]))
        );
        assert_eq!(tool.input_schema.get("additionalProperties"), Some(&serde_json::Value::Bool(false)));
    }

    /// Plugin/MCP tools may send unusual input_schema shapes (missing "type",
    /// extra fields like "$schema", etc.). The proxy must deserialize and
    /// pass them through without error.
    #[test]
    fn test_plugin_tool_unusual_schema_passthrough() {
        let mut rules = minimal_ruleset();
        rules.unmapped_policy = UnmappedPolicy::Passthrough;

        // Simulate what a plugin tool might send: no "type", just "properties"
        let req: MessagesRequest = serde_json::from_value(serde_json::json!({
            "model": "test",
            "max_tokens": 1024,
            "messages": [],
            "tools": [
                {
                    "name": "claude_mem_search",
                    "description": "Search memory",
                    "input_schema": {
                        "properties": {
                            "query": {"type": "string", "description": "Search query"}
                        }
                    }
                },
                {
                    "name": "normal_tool",
                    "description": "Normal tool",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "arg": {"type": "string"}
                        },
                        "required": ["arg"]
                    }
                }
            ]
        }))
        .expect("request with unusual plugin tool schema should deserialize");

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();

        // Both tools should pass through unchanged
        assert_eq!(result.tools.len(), 2);
        assert_eq!(result.tools[0].name, "claude_mem_search");
        // The unusual schema should be preserved exactly
        assert!(result.tools[0].input_schema.get("type").is_none());
        assert!(result.tools[0].input_schema.get("properties").is_some());
        // Normal tool should also be fine
        assert_eq!(result.tools[1].input_schema.get("type"), Some(&serde_json::json!("object")));
    }

    #[test]
    fn test_property_rename() {
        let mut rules = minimal_ruleset();
        rules.property_renames.push(super::super::PropertyRename {
            from: "session_id".into(),
            to: "thread_id".into(),
        });

        let mut input = serde_json::json!({
            "session_id": "abc123",
            "nested": {
                "session_id": "def456"
            }
        });

        rename_properties_in_value(&mut input, &rules.property_renames);

        assert!(input.get("thread_id").is_some());
        assert!(input.get("session_id").is_none());
        assert!(input["nested"].get("thread_id").is_some());
        assert!(input["nested"].get("session_id").is_none());
    }

    #[test]
    fn test_system_prompt_replacement() {
        let mut rules = minimal_ruleset();
        rules.system_prompt_detect = Some("You are Claude Code".into());
        rules.system_prompt_replacement = Some("You are the canonical assistant.".into());

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: Some(SystemPrompt::String(
                "You are Claude Code, an AI assistant.".into(),
            )),
            messages: vec![],
            tools: vec![],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        // After replacement, system prompt has 2 blocks: identity line + replacement text
        let blocks = match result.system.unwrap() {
            SystemPrompt::Blocks(b) => b,
            _ => panic!("expected Blocks"),
        };
        assert_eq!(blocks.len(), 2);
        match &blocks[0] {
            SystemBlock::Text { text, cache_control } => {
                assert_eq!(text, "You are Claude Code, Anthropic's official CLI for Claude.\n");
                assert!(cache_control.is_some());
            }
        }
        match &blocks[1] {
            SystemBlock::Text { text, .. } => {
                assert_eq!(text, "You are the canonical assistant.");
            }
        }
    }

    #[test]
    fn test_strip_trailing_prefill() {
        let rules = minimal_ruleset();

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: None,
            messages: vec![
                Message {
                    role: Role::User,
                    content: MessageContent::String("hello".into()),
                },
                Message {
                    role: Role::Assistant,
                    content: MessageContent::String("prefill".into()),
                },
            ],
            tools: vec![],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        assert_eq!(result.messages.len(), 1);
        assert_eq!(result.messages[0].role, Role::User);
    }

    #[test]
    fn test_text_replacements() {
        let mut rules = minimal_ruleset();
        rules.text_replacements.push(TextReplacement {
            find: "old-url.com".into(),
            replace: "new-url.com".into(),
        });

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: Some(SystemPrompt::Blocks(vec![SystemBlock::Text {
                text: "Visit old-url.com for help.".into(),
                cache_control: None,
            }])),
            messages: vec![Message {
                role: Role::User,
                content: MessageContent::Blocks(vec![ContentBlock::Text {
                    text: "See old-url.com".into(),
                    cache_control: None,
                }]),
            }],
            tools: vec![],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();

        // System prompt should be replaced
        let sys_text = result.system.unwrap().text_content();
        assert!(sys_text.contains("new-url.com"));
        assert!(!sys_text.contains("old-url.com"));

        // Message text should be preserved (NOT replaced)
        if let MessageContent::Blocks(blocks) = &result.messages[0].content {
            if let ContentBlock::Text { text, .. } = &blocks[0] {
                assert!(
                    text.contains("old-url.com"),
                    "message text should NOT be transformed"
                );
            } else {
                panic!("expected text block");
            }
        } else {
            panic!("expected blocks");
        }
    }

    #[test]
    fn test_billing_block_injection() {
        let mut rules = minimal_ruleset();
        rules.inject_billing_block = true;
        rules.billing_cc_version = Some("2.1.97".into());

        let req = MessagesRequest {
            model: "test".into(),
            max_tokens: 1024,
            temperature: None,
            system: Some(SystemPrompt::Blocks(vec![SystemBlock::Text {
                text: "You are an assistant.".into(),
                cache_control: None,
            }])),
            messages: vec![],
            tools: vec![],
            tool_choice: None,
            metadata: None,
            stream: false,
            thinking: None,
            top_p: None,
            top_k: None,
            stop_sequences: None,
            extra: serde_json::Map::new(),
        };

        let result = apply_request_rules(req, &rules, "test-session", "test-device").unwrap();
        if let Some(SystemPrompt::Blocks(blocks)) = &result.system {
            assert_eq!(blocks.len(), 2);
            if let SystemBlock::Text { text, .. } = &blocks[0] {
                assert!(text.contains("2.1.97"));
                assert!(text.contains("billing"));
            } else {
                panic!("expected text block at index 0");
            }
        } else {
            panic!("expected system blocks");
        }
    }
}
