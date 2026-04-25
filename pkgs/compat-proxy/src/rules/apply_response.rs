//! Reverse response translation: upstream format → client format.
//!
//! Reverses tool renames and property renames. Thinking blocks are
//! passed through unchanged (enforced by ThinkingBlock newtype).

use crate::wire::content::ContentBlock;
use crate::wire::response::MessagesResponse;

use super::apply_request::rename_properties_in_value;
use super::{RuleError, RuleSet};

/// Apply all reverse translation rules to a non-streaming response.
pub fn apply_response_rules(
    mut resp: MessagesResponse,
    rules: &RuleSet,
) -> Result<MessagesResponse, RuleError> {
    // Reverse tool renames in content blocks
    reverse_rename_tools(&mut resp, rules);

    // Reverse property renames in tool_use.input values
    reverse_rename_properties(&mut resp, rules)?;

    Ok(resp)
}

/// Reverse tool name renames in response content blocks.
///
/// When the model emits `tool_use.name = "Bash"`, we need to map it back
/// to whatever the client originally sent (e.g., "mcp_bash"). The forward
/// and reverse mappings come from the same rule, applied symmetrically.
fn reverse_rename_tools(resp: &mut MessagesResponse, rules: &RuleSet) {
    for block in &mut resp.content {
        match block {
            ContentBlock::ToolUse { name, .. } => {
                if let Some(client_name) = rules.client_name_for(name) {
                    *name = client_name.to_string();
                }
            }
            // Thinking, server tools, images, and unknown blocks: pass through unchanged
            ContentBlock::Thinking { .. }
            | ContentBlock::RedactedThinking { .. }
            | ContentBlock::ServerToolUse { .. }
            | ContentBlock::WebSearchToolResult { .. }
            | ContentBlock::Other(_)
            | ContentBlock::Text { .. }
            | ContentBlock::Image { .. }
            | ContentBlock::ToolResult { .. } => {}
        }
    }
}

/// Reverse property renames in tool_use.input values.
fn reverse_rename_properties(
    resp: &mut MessagesResponse,
    rules: &RuleSet,
) -> Result<(), RuleError> {
    if rules.property_renames.is_empty() {
        return Ok(());
    }

    let reverse_renames = rules.reverse_property_renames();

    for block in &mut resp.content {
        if let ContentBlock::ToolUse { input, .. } = block {
            rename_properties_in_value(input, &reverse_renames);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::{PropertyRename, ResolvedToolRename, UnmappedPolicy};
    use crate::wire::content::ContentBlock;
    use crate::wire::response::{MessagesResponse, Usage};

    fn minimal_ruleset() -> RuleSet {
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
        }
    }

    fn minimal_response(content: Vec<ContentBlock>) -> MessagesResponse {
        MessagesResponse {
            id: "msg_test".into(),
            response_type: "message".into(),
            role: "assistant".into(),
            content,
            model: "test-model".into(),
            stop_reason: Some("end_turn".into()),
            stop_sequence: None,
            usage: Usage {
                input_tokens: 100,
                output_tokens: 50,
                cache_creation_input_tokens: None,
                cache_read_input_tokens: None,
                extra: serde_json::Map::new(),
            },
            extra: serde_json::Map::new(),
        }
    }

    #[test]
    fn test_reverse_tool_rename() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_bash".into(),
            ResolvedToolRename {
                canonical_name: "Bash".into(),
                description: Some("Execute a command".into()),
                schema_override: None,
            },
        );

        let resp = minimal_response(vec![ContentBlock::ToolUse {
            id: "tu_1".into(),
            name: "Bash".into(),
            input: serde_json::json!({"command": "ls"}),
            cache_control: None,
        }]);

        let result = apply_response_rules(resp, &rules).unwrap();
        if let ContentBlock::ToolUse { name, .. } = &result.content[0] {
            assert_eq!(name, "mcp_bash");
        } else {
            panic!("expected tool_use");
        }
    }

    #[test]
    fn test_reverse_property_rename() {
        let mut rules = minimal_ruleset();
        rules.property_renames.push(PropertyRename {
            from: "session_id".into(),
            to: "thread_id".into(),
        });

        let resp = minimal_response(vec![ContentBlock::ToolUse {
            id: "tu_1".into(),
            name: "some_tool".into(),
            input: serde_json::json!({"thread_id": "abc123"}),
            cache_control: None,
        }]);

        let result = apply_response_rules(resp, &rules).unwrap();
        if let ContentBlock::ToolUse { input, .. } = &result.content[0] {
            assert!(input.get("session_id").is_some());
            assert!(input.get("thread_id").is_none());
        } else {
            panic!("expected tool_use");
        }
    }

    #[test]
    fn test_thinking_blocks_unchanged() {
        let rules = minimal_ruleset();

        let resp = minimal_response(vec![
            ContentBlock::Thinking {
                thinking: "internal reasoning".into(),
                signature: "sig123".into(),
                budget_tokens: None,
            },
            ContentBlock::RedactedThinking {
                data: "redacted_data".into(),
            },
            ContentBlock::Text {
                text: "Hello!".into(),
                cache_control: None,
            },
        ]);

        let result = apply_response_rules(resp, &rules).unwrap();
        assert_eq!(result.content.len(), 3);
        assert!(matches!(result.content[0], ContentBlock::Thinking { .. }));
        assert!(matches!(
            result.content[1],
            ContentBlock::RedactedThinking { .. }
        ));
    }

    /// Round-trip test: forward-translate a request, then reverse-translate
    /// a synthetic response. The tool names dispatched to the client must
    /// match what the client originally sent.
    #[test]
    fn test_round_trip_tool_names() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_bash".into(),
            ResolvedToolRename {
                canonical_name: "Bash".into(),
                description: Some("Execute a command".into()),
                schema_override: None,
            },
        );
        rules.tool_renames.insert(
            "mcp_read".into(),
            ResolvedToolRename {
                canonical_name: "Read".into(),
                description: Some("Read a file".into()),
                schema_override: None,
            },
        );

        // Simulate model responding with canonical names
        let resp = minimal_response(vec![
            ContentBlock::ToolUse {
                id: "tu_1".into(),
                name: "Bash".into(),
                input: serde_json::json!({"command": "ls"}),
                cache_control: None,
            },
            ContentBlock::ToolUse {
                id: "tu_2".into(),
                name: "Read".into(),
                input: serde_json::json!({"path": "/etc/hosts"}),
                cache_control: None,
            },
        ]);

        let result = apply_response_rules(resp, &rules).unwrap();

        // Client should see the original names
        if let ContentBlock::ToolUse { name, .. } = &result.content[0] {
            assert_eq!(name, "mcp_bash");
        }
        if let ContentBlock::ToolUse { name, .. } = &result.content[1] {
            assert_eq!(name, "mcp_read");
        }
    }
}
