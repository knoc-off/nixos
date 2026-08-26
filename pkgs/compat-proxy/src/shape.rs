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

/// Everything the shaper needs to know about the caller.
pub struct Context<'a> {
    pub cc_version: &'a str,
    pub session_id: &'a str,
    pub device_id: &'a str,
    pub max_tokens: Option<u64>,
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

    inject_metadata(obj, ctx.session_id, ctx.device_id);
    inject_thinking(obj);
    inject_context_management(obj);
    strip_tool_choice_auto(obj);

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
/// Without this the client pays full price for a system prompt that is
/// identical on every request. Blocks that already carry an explicit
/// `cache_control` are left alone.
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
        block
            .entry("cache_control")
            .or_insert_with(|| cache.clone());
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
             cc_entrypoint=cli; cch=00000;"
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

/// Text of the first user message, which seeds the billing fingerprint.
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
            Some(Value::Array(blocks)) => blocks
                .iter()
                .find(|b| b.get("type").and_then(Value::as_str) == Some("text"))
                .and_then(|b| b.get("text"))
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string(),
            _ => String::new(),
        };
    }
    String::new()
}

/// Real CC sends `metadata.user_id` as a JSON *string* of its identifiers.
fn inject_metadata(obj: &mut Map<String, Value>, session_id: &str, device_id: &str) {
    let user_id = json!({ "device_id": device_id, "session_id": session_id }).to_string();
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
            max_tokens: Some(64000),
        }
    }

    fn shaped(mut req: Value) -> Value {
        to_claude_code(&mut req, &ctx());
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

        assert!(system[0].get("cache_control").is_none());
        assert_eq!(system[1]["cache_control"]["ttl"], "1h");
        assert!(system[2].get("cache_control").is_none());
        assert_eq!(system[3]["cache_control"]["ttl"], "1h");
    }

    #[test]
    fn preserves_unknown_fields() {
        let out = shaped(json!({ "model": "claude-sonnet-4", "some_new_field": { "a": 1 } }));
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
    fn metadata_user_id_is_a_json_string() {
        let out = shaped(json!({ "model": "claude-sonnet-4" }));
        let user_id = out["metadata"]["user_id"].as_str().unwrap();
        let parsed: Value = serde_json::from_str(user_id).unwrap();
        assert_eq!(parsed["session_id"], "session");
        assert_eq!(parsed["device_id"], "device");
    }
}
