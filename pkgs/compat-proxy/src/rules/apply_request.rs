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
use crate::wire::request::{
    MessageContent, Metadata, MessagesRequest, Role, SystemBlock, SystemPrompt,
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

    // Step 7: Billing block injection (with SHA256 fingerprint)
    inject_billing_block(&mut req, rules, &mut changes);

    // Step 8: Inject metadata (device_id + session_id)
    inject_metadata(&mut req, session_id, device_id, &mut changes);

    // Step 9: Strip trailing assistant prefill
    strip_trailing_prefill(&mut req, &mut changes);

    // Step 10: Apply unknown-field rules. Anything unhandled still warns
    // so we can add explicit rules for it (these fields are fingerprint
    // signals -- real Claude Code only sends documented Anthropic fields).
    apply_unknown_field_rules(&mut req, rules, &mut changes);

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
                let client_required = tool.input_schema.required.take();
                let client_additional_props = tool.input_schema.additional_properties.take();

                tool.input_schema = schema_override.clone();

                // Merge: prefer registry values, fall back to client values
                if tool.input_schema.required.is_none() {
                    tool.input_schema.required = client_required;
                }
                if tool.input_schema.additional_properties.is_none() {
                    tool.input_schema.additional_properties = client_additional_props;
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
fn replace_system_prompt(req: &mut MessagesRequest, rules: &RuleSet, changes: &mut Vec<String>) {
    let detect = match &rules.system_prompt_detect {
        Some(d) => d,
        None => return,
    };

    let replacement = match &rules.system_prompt_replacement {
        Some(r) => r,
        None => return,
    };

    if let Some(ref system) = req.system {
        let text = system.text_content();
        if text.contains(detect.as_str()) {
            let before_len = text.len();
            let after_len = replacement.len();
            req.system = Some(SystemPrompt::Blocks(vec![SystemBlock::Text {
                text: replacement.clone(),
                cache_control: None,
            }]));
            changes.push(format!(
                "system prompt: replaced ({before_len} → {after_len} chars)"
            ));
        }
    }
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

/// Step 8: Inject metadata (device_id + session_id) matching real CC format.
///
/// Real CC sends: metadata.user_id = JSON.stringify({device_id, session_id})
fn inject_metadata(
    req: &mut MessagesRequest,
    session_id: &str,
    device_id: &str,
    changes: &mut Vec<String>,
) {
    let meta_value = serde_json::json!({
        "device_id": device_id,
        "session_id": session_id,
    });

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
                input_schema: InputSchema {
                    schema_type: "object".into(),
                    properties: None,
                    required: None,
                    additional_properties: None,
                },
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
                    input_schema: InputSchema {
                        schema_type: "object".into(),
                        properties: None,
                        required: None,
                        additional_properties: None,
                    },
                    cache_control: None,
                },
                Tool {
                    name: "mcp_bash".into(),
                    description: None,
                    input_schema: InputSchema {
                        schema_type: "object".into(),
                        properties: None,
                        required: None,
                        additional_properties: None,
                    },
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
                input_schema: InputSchema {
                    schema_type: "object".into(),
                    properties: None,
                    required: None,
                    additional_properties: None,
                },
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
                input_schema: client_schema.clone(),
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
        let props = tool.input_schema.properties.as_ref().unwrap();
        assert!(props["todos"]["items"]["properties"]["content"].is_object());
        assert_eq!(
            tool.input_schema.required.as_deref(),
            Some(&["todos".to_string()][..])
        );
        assert_eq!(tool.input_schema.additional_properties, Some(serde_json::Value::Bool(false)));
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
        let text = result.system.unwrap().text_content();
        assert_eq!(text, "You are the canonical assistant.");
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
