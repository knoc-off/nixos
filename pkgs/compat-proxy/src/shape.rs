//! Claude Code request shaping.
//!
//! Anthropic's OAuth endpoint only serves requests that look like Claude
//! Code, so everything here exists to reproduce what the real CLI puts on
//! the wire. The client is expected to supply its own system prompt and
//! tool set; this module only adds the parts that are properties of the
//! *transport* rather than of the agent.
//!
//! Operates on `serde_json::Value` rather than a typed model on purpose.
//! A typed round-trip silently drops any field Anthropic adds that we
//! haven't modelled; a `Value` carries unknown fields through untouched,
//! which is the whole reason this proxy can stay small.

use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

/// The identity line real CC sends as its first system block. The OAuth
/// endpoint checks for it.
const IDENTITY: &str = "You are Claude Code, Anthropic's official CLI for Claude.\n";

/// Billing fingerprint constants, from real CC's `utils/fingerprint.ts`.
const BILLING_HASH_SALT: &str = "59cf53e54c78";
const BILLING_HASH_INDICES: [usize; 3] = [4, 7, 20];

/// Anthropic allows at most 4 cache breakpoints per request. We claim two
/// (identity + last system block) and leave the rest for the client.
const CACHE_BREAKPOINTS: usize = 2;

/// opencode's own internal tool ids. Real Claude Code never sends these --
/// it sends `Bash`, `Read`, `TodoWrite`, ... -- so seeing one here means
/// the wire-name aliasing in pkgs/opencode's `anthropic-messages.ts` patch
/// did not run for this request.
///
/// This is worth shouting about because the failure is silent and the
/// upstream error is actively misleading. opencode only applies the alias
/// on its *native* LLM runtime; if that runtime bails (most easily by
/// having an `oauth` entry for anthropic in opencode's `auth.json`, which
/// makes `native-runtime.ts` return "OAuth auth requires a provider fetch
/// override") it silently falls back to the AI SDK path, which has no
/// aliasing. The request then goes out with these names and Anthropic
/// rejects it with "You're out of extra usage" -- a quota-shaped message
/// for what is really a request-content rejection. `todowrite` alone is
/// enough to trigger it, verified by live differential testing.
const OPENCODE_TOOL_IDS: &[&str] = &[
    "apply_patch",
    "bash",
    "edit",
    "glob",
    "grep",
    "invalid",
    "lsp",
    "plan_exit",
    "question",
    "read",
    "skill",
    "task",
    "todowrite",
    "webfetch",
    "websearch",
    "write",
];

/// Everything the shaper needs to know about the caller.
pub struct Context<'a> {
    pub cc_version: &'a str,
    pub session_id: &'a str,
    pub device_id: &'a str,
    /// The account UUID real CC reads from `~/.claude.json`'s
    /// `oauthAccount.accountUuid` and includes in `metadata.user_id`.
    /// Absent it entirely on read failure rather than guessing — real CC
    /// only omits it when it genuinely doesn't have one either.
    pub account_uuid: Option<&'a str>,
    pub max_tokens: Option<u64>,
    /// Inject `thinking: {type: "adaptive"}` on models the caller didn't
    /// already request thinking on. Off by default: "adaptive" only exists
    /// on specific newer model families (Opus/Sonnet 4.6+) and the API
    /// 400s outright on anything older — there is no way to tell which
    /// from the model string alone, so guessing is worse than leaving the
    /// client's own `thinking` field (if any) untouched.
    pub inject_thinking: bool,
    /// Inject `context_management` clearing stale thinking blocks. Tied to
    /// the same "adaptive" assumption as `inject_thinking` above and just
    /// as unsafe to guess at, so also off by default.
    pub inject_context_management: bool,
    /// Drop `tool_choice: {type: "auto"}` (real CC omits it rather than
    /// sending the default explicitly). Cosmetic fidelity, not a
    /// correctness requirement, so off by default.
    pub strip_tool_choice_auto: bool,
}

/// Rewrite a `/v1/messages` body into Claude Code's wire shape, in place.
///
/// Ordering matters: the billing block is computed from the first user
/// message and must end up *before* the identity block, matching real CC's
/// block layout of `[billing, identity, prompt...]`.
pub fn to_claude_code(req: &mut Value, ctx: &Context<'_>) {
    let Some(obj) = req.as_object_mut() else {
        tracing::warn!("request body is not a JSON object; forwarding unshaped");
        return;
    };

    strip_trailing_prefill(obj);

    let billing = billing_block(obj, ctx.cc_version);
    let system = normalize_system(obj);
    system.insert(0, json!({ "type": "text", "text": IDENTITY }));
    system.insert(0, billing);
    apply_cache_control(system);
    strip_tool_cache_control(obj);
    upgrade_message_cache_control(obj);
    warn_on_unaliased_tools(obj);

    inject_metadata(obj, ctx.session_id, ctx.device_id, ctx.account_uuid);
    if ctx.inject_thinking {
        inject_thinking(obj);
    }
    if ctx.inject_context_management {
        inject_context_management(obj);
    }
    if ctx.strip_tool_choice_auto {
        strip_tool_choice_auto(obj);
    }

    if let Some(max) = ctx.max_tokens {
        obj.insert("max_tokens".into(), json!(max));
    }
}

/// Coerce `system` into block form and return it for further editing.
///
/// The field is absent for bare requests and a plain string for simple
/// clients; both have to become an array before we can prepend blocks.
fn normalize_system(obj: &mut Map<String, Value>) -> &mut Vec<Value> {
    let existing = obj.remove("system");
    let blocks = match existing {
        Some(Value::Array(blocks)) => blocks,
        Some(Value::String(text)) => vec![json!({ "type": "text", "text": text })],
        Some(other) => {
            tracing::warn!("unexpected system field type; wrapping as text block");
            vec![json!({ "type": "text", "text": other.to_string() })]
        }
        None => Vec::new(),
    };

    obj.insert("system".into(), Value::Array(blocks));
    obj.get_mut("system")
        .and_then(Value::as_array_mut)
        .expect("just inserted an array")
}

/// Stamp `cache_control` on the identity block and the last system block.
///
/// `ttl: "1h"`, matching real CC's own breakpoints (confirmed by live
/// capture: both system blocks and its first user-message breakpoint use
/// `ttl: "1h"`, and it sets none at all on `tools`). Anthropic requires
/// breakpoint TTLs to be non-increasing across the request (`tools`, then
/// `system`, then `messages`) -- an earlier version of this function used
/// plain `ephemeral` (5m) here specifically to sit below opencode's own
/// default 5m breakpoint on its last tool, but that only papered over the
/// real fix: `strip_tool_cache_control` below removes that tool breakpoint
/// entirely, so `1h` here no longer conflicts with anything downstream.
/// Always overwrites: opencode's own caching strategy already stamps a
/// plain (5m) breakpoint on the last system block, and leaving that alone
/// would violate the same ordering rule one block later.
fn apply_cache_control(system: &mut [Value]) {
    let cache = json!({ "type": "ephemeral", "ttl": "1h" });


    // Index 0 is the billing block, which real CC leaves uncached.
    let mut targets = vec![1usize];
    if system.len() > 2 {
        targets.push(system.len() - 1);
    }
    targets.truncate(CACHE_BREAKPOINTS);

    for index in targets {
        let Some(block) = system.get_mut(index).and_then(Value::as_object_mut) else {
            continue;
        };
        block.insert("cache_control".into(), cache.clone());
    }
}

/// Remove any `cache_control` opencode placed on `tools[*]`.
///
/// Real CC never caches on tools (confirmed by live capture: 28 tools, zero
/// breakpoints) -- it relies entirely on the system-prompt breakpoints
/// above. opencode's own cache-strategy logic defaults to putting a 5m
/// breakpoint on the last tool, which both looks wrong next to real CC's
/// shape and, combined with the `1h` system breakpoints above, would
/// violate Anthropic's non-increasing-TTL-ordering rule (`tools` ->
/// `system` -> `messages`) if left in place.
fn strip_tool_cache_control(obj: &mut Map<String, Value>) {
    let Some(tools) = obj.get_mut("tools").and_then(Value::as_array_mut) else {
        return;
    };
    for tool in tools {
        if let Some(tool) = tool.as_object_mut() {
            tool.remove("cache_control");
        }
    }
}

/// Shout if opencode's internal tool ids reached the wire.
///
/// See `OPENCODE_TOOL_IDS`. This proxy deliberately does *not* rename them
/// itself: the model would then answer with `tool_use` blocks named
/// `TodoWrite`, which opencode wouldn't route back to its own `todowrite`
/// handler without also rewriting the streaming response. Renaming belongs
/// in opencode, where both directions are one symbol. All this can do is
/// make the breakage legible instead of surfacing as a bogus quota error.
fn warn_on_unaliased_tools(obj: &Map<String, Value>) {
    let Some(tools) = obj.get("tools").and_then(Value::as_array) else {
        return;
    };
    let leaked: Vec<&str> = tools
        .iter()
        .filter_map(|t| t.get("name").and_then(Value::as_str))
        .filter(|name| OPENCODE_TOOL_IDS.contains(name))
        .collect();

    if leaked.is_empty() {
        return;
    }
    tracing::error!(
        tools = leaked.join(","),
        "opencode's internal tool names reached the wire; Anthropic will reject \
         this request with a misleading \"out of extra usage\" error. The \
         tool-name aliasing only runs on opencode's native LLM runtime -- check \
         that OPENCODE_EXPERIMENTAL_NATIVE_LLM is set and that opencode's \
         auth.json has no `oauth` entry for anthropic (an oauth entry disables \
         the native runtime and silently falls back to the AI SDK path)"
    );
}

/// Rewrite any existing message-level `cache_control` to `ttl: "1h"`.
///
/// opencode places its own breakpoint (plain `ephemeral`, no `ttl`) on the
/// last message when it decides the conversation is worth caching. Real CC
/// uses `ttl: "1h"` for this too (confirmed by live capture). This only
/// upgrades blocks that already have a breakpoint -- it never adds one.
fn upgrade_message_cache_control(obj: &mut Map<String, Value>) {    let Some(messages) = obj.get_mut("messages").and_then(Value::as_array_mut) else {
        return;
    };
    for message in messages {
        let Some(content) = message.get_mut("content").and_then(Value::as_array_mut) else {
            continue;
        };
        for block in content {
            let Some(block) = block.as_object_mut() else {
                continue;
            };
            if block.contains_key("cache_control") {
                block.insert("cache_control".into(), json!({ "type": "ephemeral", "ttl": "1h" }));
            }
        }
    }
}

/// Build the billing block real CC prepends to the system prompt.
fn billing_block(obj: &Map<String, Value>, cc_version: &str) -> Value {
    let first_user_text = first_user_text(obj);
    let fingerprint = billing_fingerprint(&first_user_text, cc_version);
    json!({
        "type": "text",
        "text": format!(
            "x-anthropic-billing-header: cc_version={cc_version}.{fingerprint}; \
             cc_entrypoint=cli;"
        ),
    })
}

/// `SHA256(salt + msg[4] + msg[7] + msg[20] + version)[:3]`, matching CC's
/// `computeFingerprint()`. Missing characters fall back to `'0'`.
fn billing_fingerprint(first_user_text: &str, cc_version: &str) -> String {
    let chars: String = BILLING_HASH_INDICES
        .iter()
        .map(|&i| first_user_text.chars().nth(i).unwrap_or('0'))
        .collect();

    let digest = Sha256::digest(format!("{BILLING_HASH_SALT}{chars}{cc_version}").as_bytes());
    digest
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>()
        .chars()
        .take(3)
        .collect()
}

/// Text of the first *genuine* user message, which seeds the billing
/// fingerprint.
///
/// opencode prepends `<system-reminder>` blocks (available agent types,
/// skills, etc.) to the first user turn's content array; real CC's own
/// fingerprint is seeded from the actual prompt text, not these injected
/// blocks (confirmed by live capture: matching CC's captured fingerprint
/// required skipping three leading `<system-reminder>` blocks to reach the
/// real prompt). Falls back to the first text block if every block is a
/// reminder, so this never produces an empty seed unnecessarily.
fn first_user_text(obj: &Map<String, Value>) -> String {
    let Some(messages) = obj.get("messages").and_then(Value::as_array) else {
        return String::new();
    };

    for message in messages {
        if message.get("role").and_then(Value::as_str) != Some("user") {
            continue;
        }
        return match message.get("content") {
            Some(Value::String(text)) => text.clone(),
            Some(Value::Array(blocks)) => {
                let texts: Vec<&str> = blocks
                    .iter()
                    .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
                    .filter_map(|b| b.get("text").and_then(Value::as_str))
                    .collect();
                texts
                    .iter()
                    .find(|t| !t.starts_with("<system-reminder>"))
                    .or_else(|| texts.first())
                    .map(|t| t.to_string())
                    .unwrap_or_default()
            }
            _ => String::new(),
        };
    }
    String::new()
}

/// Real CC sends `metadata.user_id` as a JSON *string* of its identifiers.
fn inject_metadata(
    obj: &mut Map<String, Value>,
    session_id: &str,
    device_id: &str,
    account_uuid: Option<&str>,
) {
    let mut fields = Map::new();
    fields.insert("device_id".into(), json!(device_id));
    if let Some(uuid) = account_uuid {
        fields.insert("account_uuid".into(), json!(uuid));
    }
    fields.insert("session_id".into(), json!(session_id));
    let user_id = Value::Object(fields).to_string();
    obj.insert("metadata".into(), json!({ "user_id": user_id }));
}

/// Adaptive thinking, on the models that support it.
///
/// Anthropic rejects an explicit `temperature` alongside thinking, so it
/// goes away whenever thinking is in play — including when the *client*
/// asked for thinking itself.
fn inject_thinking(obj: &mut Map<String, Value>) {
    if !supports_thinking(obj) {
        return;
    }
    if !obj.contains_key("thinking") {
        obj.insert("thinking".into(), json!({ "type": "adaptive" }));
    }
    obj.remove("temperature");
}

/// Real CC sends this on thinking-capable models to drop stale reasoning
/// blocks from the context rather than resending them.
fn inject_context_management(obj: &mut Map<String, Value>) {
    if !supports_thinking(obj) || obj.contains_key("context_management") {
        return;
    }
    obj.insert(
        "context_management".into(),
        json!({ "edits": [{ "keep": "all", "type": "clear_thinking_20251015" }] }),
    );
}

/// Opus and Sonnet support adaptive thinking; Haiku does not.
fn supports_thinking(obj: &Map<String, Value>) -> bool {
    obj.get("model")
        .and_then(Value::as_str)
        .map(str::to_lowercase)
        .is_some_and(|m| m.contains("opus") || m.contains("sonnet"))
}

/// Real CC omits `tool_choice` entirely rather than sending the default.
fn strip_tool_choice_auto(obj: &mut Map<String, Value>) {
    let is_auto = obj
        .get("tool_choice")
        .and_then(|c| c.get("type"))
        .and_then(Value::as_str)
        == Some("auto");
    if is_auto {
        obj.remove("tool_choice");
    }
}

/// Drop trailing assistant messages.
///
/// Some clients send one as a prefill hint. Upstream rejects them, and CC
/// never sends them.
fn strip_trailing_prefill(obj: &mut Map<String, Value>) {
    let Some(messages) = obj.get_mut("messages").and_then(Value::as_array_mut) else {
        return;
    };
    while messages
        .last()
        .and_then(|m| m.get("role"))
        .and_then(Value::as_str)
        == Some("assistant")
    {
        messages.pop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx() -> Context<'static> {
        Context {
            cc_version: "2.1.97",
            session_id: "session",
            device_id: "device",
            account_uuid: Some("account"),
            max_tokens: Some(64000),
            inject_thinking: true,
            inject_context_management: true,
            strip_tool_choice_auto: true,
        }
    }

    fn shaped(mut req: Value) -> Value {
        to_claude_code(&mut req, &ctx());
        req
    }

    fn shaped_with_version(mut req: Value, cc_version: &'static str) -> Value {
        let mut c = ctx();
        c.cc_version = cc_version;
        to_claude_code(&mut req, &c);
        req
    }

    #[test]
    fn prepends_billing_then_identity() {
        let out = shaped(json!({ "model": "claude-sonnet-4", "system": "custom prompt" }));
        let system = out["system"].as_array().unwrap();

        assert_eq!(system.len(), 3);
        assert!(system[0]["text"]
            .as_str()
            .unwrap()
            .starts_with("x-anthropic-billing-header: cc_version=2.1.97."));
        assert_eq!(system[1]["text"], IDENTITY);
        assert_eq!(system[2]["text"], "custom prompt");
    }

    #[test]
    fn absent_system_still_gets_the_identity_block() {
        let out = shaped(json!({ "model": "claude-sonnet-4" }));
        let system = out["system"].as_array().unwrap();
        assert_eq!(system.len(), 2);
        assert_eq!(system[1]["text"], IDENTITY);
    }

    #[test]
    fn caches_identity_and_last_block_but_not_billing() {
        let out = shaped(json!({
            "model": "claude-sonnet-4",
            "system": [{ "type": "text", "text": "a" }, { "type": "text", "text": "b" }],
        }));
        let system = out["system"].as_array().unwrap();

        let ttl_1h = json!({ "type": "ephemeral", "ttl": "1h" });
        assert!(system[0].get("cache_control").is_none());
        assert_eq!(system[1]["cache_control"], ttl_1h);
        assert!(system[2].get("cache_control").is_none());
        assert_eq!(system[3]["cache_control"], ttl_1h);
    }

    #[test]
    fn strips_tool_cache_control() {        let out = shaped(json!({
            "model": "claude-sonnet-4",
            "tools": [
                { "name": "bash", "cache_control": { "type": "ephemeral" } },
                { "name": "read" },
            ],
        }));
        let tools = out["tools"].as_array().unwrap();
        assert!(tools[0].get("cache_control").is_none());
        assert!(tools[1].get("cache_control").is_none());
    }

    #[test]
    fn upgrades_message_cache_control_to_1h() {
        let out = shaped(json!({
            "model": "claude-sonnet-4",
            "messages": [{
                "role": "user",
                "content": [
                    { "type": "text", "text": "hi", "cache_control": { "type": "ephemeral" } },
                    { "type": "text", "text": "uncached" },
                ],
            }],
        }));
        let content = out["messages"][0]["content"].as_array().unwrap();
        assert_eq!(content[0]["cache_control"], json!({ "type": "ephemeral", "ttl": "1h" }));
        assert!(content[1].get("cache_control").is_none());
    }

    /// The exact tool list captured from a jail session that Anthropic
    /// rejected. Every one of these lowercase ids must be recognised as
    /// un-aliased, and the Claude Code names and MCP/plugin tools alongside
    /// them must not produce false positives.
    #[test]
    fn detects_unaliased_opencode_tool_names() {
        let captured = [
            "bash", "edit", "glob", "grep", "question", "read", "skill", "task", "todowrite",
            "webfetch", "write",
        ];
        for name in captured {
            assert!(
                OPENCODE_TOOL_IDS.contains(&name),
                "{name} should be detected as an un-aliased opencode tool id"
            );
        }

        // Real CC names, MCP tools and host plugins share the wire with them
        // and must never be flagged.
        for name in [
            "Bash",
            "Edit",
            "Glob",
            "Grep",
            "Read",
            "Task",
            "TodoWrite",
            "WebFetch",
            "Write",
            "AskUserQuestion",
            "claude_mem_search",
            "host_exec",
            "list_mcp_resources",
            "read_mcp_resource",
            "mcp__context7__query-docs",
            "mcp__nixos__nix",
        ] {
            assert!(
                !OPENCODE_TOOL_IDS.contains(&name),
                "{name} must not be flagged as an opencode tool id"
            );
        }
    }

    #[test]
    fn preserves_unknown_fields() {        let out = shaped(json!({ "model": "claude-sonnet-4", "some_new_field": { "a": 1 } }));
        assert_eq!(out["some_new_field"]["a"], 1);
    }

    #[test]
    fn thinking_replaces_temperature_on_sonnet() {
        let out = shaped(json!({ "model": "claude-sonnet-4", "temperature": 0.5 }));
        assert_eq!(out["thinking"]["type"], "adaptive");
        assert!(out.get("temperature").is_none());
        assert_eq!(out["context_management"]["edits"][0]["keep"], "all");
    }

    #[test]
    fn haiku_keeps_temperature_and_gets_no_thinking() {
        let out = shaped(json!({ "model": "claude-haiku-4", "temperature": 0.5 }));
        assert!(out.get("thinking").is_none());
        assert!(out.get("context_management").is_none());
        assert_eq!(out["temperature"], 0.5);
    }

    #[test]
    fn strips_auto_tool_choice_only() {
        let auto = shaped(json!({ "model": "claude-sonnet-4", "tool_choice": { "type": "auto" } }));
        assert!(auto.get("tool_choice").is_none());

        let forced = shaped(json!({ "model": "claude-sonnet-4", "tool_choice": { "type": "any" } }));
        assert_eq!(forced["tool_choice"]["type"], "any");
    }

    #[test]
    fn strips_trailing_assistant_prefill() {
        let out = shaped(json!({
            "model": "claude-sonnet-4",
            "messages": [
                { "role": "user", "content": "hi" },
                { "role": "assistant", "content": "prefill" },
            ],
        }));
        let messages = out["messages"].as_array().unwrap();
        assert_eq!(messages.len(), 1);
        assert_eq!(messages[0]["role"], "user");
    }

    #[test]
    fn fingerprint_is_stable_and_seeded_by_first_user_text() {
        let req = json!({
            "model": "claude-sonnet-4",
            "messages": [{ "role": "user", "content": "0123456789abcdefghijklmnop" }],
        });
        let a = shaped(req.clone());
        let b = shaped(req);
        assert_eq!(a["system"][0]["text"], b["system"][0]["text"]);

        let other = shaped(json!({
            "model": "claude-sonnet-4",
            "messages": [{ "role": "user", "content": "zzzzzzzzzzzzzzzzzzzzzzzzzz" }],
        }));
        assert_ne!(a["system"][0]["text"], other["system"][0]["text"]);
    }

    #[test]
    fn fingerprint_skips_system_reminder_blocks() {
        // Real CC prefixes the first user turn with <system-reminder> blocks
        // (agent types, skills, etc.) before the actual prompt. The
        // fingerprint must be seeded from the real prompt, not those -- this
        // reproduces a live-captured CC request (fingerprint `0e4` for
        // cc_version `2.1.204`) to prove the seed selection matches.
        let out = shaped_with_version(
            json!({
                "model": "claude-sonnet-4",
                "messages": [{
                    "role": "user",
                    "content": [
                        { "type": "text", "text": "<system-reminder>\nAvailable agent types..." },
                        { "type": "text", "text": "<system-reminder>\nThe following skills..." },
                        { "type": "text", "text": "<system-reminder>\nAs you answer..." },
                        { "type": "text", "text": "reply with exactly the word pong and nothing else" },
                    ],
                }],
            }),
            "2.1.204",
        );
        assert!(out["system"][0]["text"]
            .as_str()
            .unwrap()
            .starts_with("x-anthropic-billing-header: cc_version=2.1.204.0e4;"));
    }

    #[test]
    fn metadata_user_id_is_a_json_string() {
        let out = shaped(json!({ "model": "claude-sonnet-4" }));
        let user_id = out["metadata"]["user_id"].as_str().unwrap();
        let parsed: Value = serde_json::from_str(user_id).unwrap();
        assert_eq!(parsed["session_id"], "session");
        assert_eq!(parsed["device_id"], "device");
        assert_eq!(parsed["account_uuid"], "account");
    }

    #[test]
    fn metadata_omits_account_uuid_when_absent() {
        let mut req = json!({ "model": "claude-sonnet-4" });
        let mut ctx = ctx();
        ctx.account_uuid = None;
        to_claude_code(&mut req, &ctx);
        let user_id = req["metadata"]["user_id"].as_str().unwrap();
        let parsed: Value = serde_json::from_str(user_id).unwrap();
        assert!(parsed.get("account_uuid").is_none());
    }
}
