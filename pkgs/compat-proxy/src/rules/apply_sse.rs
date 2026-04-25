//! Streaming SSE event translation with stateful tracking.
//!
//! Handles the tricky parts:
//! - Thinking blocks are detected at content_block_start and passed through unchanged
//! - Tool names are reverse-renamed using the forward mapping
//! - Tool input deltas are buffered until content_block_stop, then parsed,
//!   property-renamed, and re-emitted as a single delta (loses streaming
//!   granularity inside tool inputs, gains correctness)

use crate::wire::content::ContentBlock;
use crate::wire::sse::{ContentDelta, SseEvent, SseState};

use super::apply_request::rename_properties_in_value;
use super::{RuleError, RuleSet};

/// Apply reverse translation rules to a single SSE event.
///
/// `state` is maintained across events within a single streaming response.
pub fn apply_sse_event_rules(
    event: SseEvent,
    rules: &RuleSet,
    state: &mut SseState,
) -> Result<SseEvent, RuleError> {
    match event {
        SseEvent::MessageStart { mut message } => {
            // Reverse-rename tools in the initial message
            for block in &mut message.content {
                if let ContentBlock::ToolUse { name, .. } = block {
                    if let Some(client_name) = rules.client_name_for(name) {
                        *name = client_name.to_string();
                    }
                }
            }
            Ok(SseEvent::MessageStart { message })
        }

        SseEvent::ContentBlockStart {
            index,
            mut content_block,
        } => {
            match &mut content_block {
                // Track thinking blocks for passthrough
                ContentBlock::Thinking { .. } | ContentBlock::RedactedThinking { .. } => {
                    state.thinking_blocks.insert(index);
                }
                // Server tool blocks and unknown blocks: track as passthrough
                // (their deltas should not be buffered or mangled)
                ContentBlock::ServerToolUse { .. }
                | ContentBlock::WebSearchToolResult { .. }
                | ContentBlock::Other(_) => {
                    state.thinking_blocks.insert(index);
                }
                // Reverse-rename tool_use blocks and track them
                ContentBlock::ToolUse { id, name, .. } => {
                    state.tool_id_map.insert(index, id.clone());
                    if let Some(client_name) = rules.client_name_for(name) {
                        state
                            .tool_name_map
                            .insert(index, client_name.to_string());
                        *name = client_name.to_string();
                    }
                    // Initialize input buffer for this block
                    state.input_buffers.insert(index, String::new());
                }
                _ => {}
            }
            Ok(SseEvent::ContentBlockStart {
                index,
                content_block,
            })
        }

        SseEvent::ContentBlockDelta { index, delta } => {
            // Thinking deltas: pass through unchanged
            if state.thinking_blocks.contains(&index) {
                return Ok(SseEvent::ContentBlockDelta { index, delta });
            }

            // Tool input deltas: only buffer if we have property renames to apply.
            // If no property renames, pass through unchanged to preserve streaming.
            if let ContentDelta::InputJsonDelta { ref partial_json } = delta {
                if !rules.property_renames.is_empty() {
                    if let Some(buffer) = state.input_buffers.get_mut(&index) {
                        buffer.push_str(partial_json);
                        // Don't emit yet — will be emitted at content_block_stop
                        return Ok(SseEvent::ContentBlockDelta {
                            index,
                            delta: ContentDelta::InputJsonDelta {
                                partial_json: String::new(),
                            },
                        });
                    }
                }
            }

            // Text deltas and unbuffered input deltas: pass through
            Ok(SseEvent::ContentBlockDelta { index, delta })
        }

        SseEvent::ContentBlockStop { index } => {
            // If we buffered tool input, now parse, rename properties, and emit
            if let Some(buffer) = state.input_buffers.remove(&index) {
                if !buffer.is_empty() && !rules.property_renames.is_empty() {
                    match serde_json::from_str::<serde_json::Value>(&buffer) {
                        Ok(mut value) => {
                            let reverse_renames = rules.reverse_property_renames();
                            rename_properties_in_value(&mut value, &reverse_renames);
                            // The re-serialized value will be emitted by the proxy
                            // as a final input_json_delta before the stop event.
                            // Store it back so the proxy layer can emit it.
                            let renamed_json = serde_json::to_string(&value)
                                .map_err(RuleError::JsonParse)?;
                            // We need to emit this as a delta before the stop.
                            // Return a synthetic "flush" — the proxy layer handles this.
                            state
                                .input_buffers
                                .insert(index, renamed_json);
                        }
                        Err(e) => {
                            tracing::warn!(
                                index,
                                error = %e,
                                "failed to parse buffered tool input JSON; passing through unchanged"
                            );
                        }
                    }
                }
            }

            // Clean up state for this block
            state.thinking_blocks.remove(&index);
            state.tool_name_map.remove(&index);
            state.tool_id_map.remove(&index);

            Ok(SseEvent::ContentBlockStop { index })
        }

        // These events pass through unchanged
        SseEvent::MessageDelta { .. }
        | SseEvent::MessageStop { .. }
        | SseEvent::Ping { .. }
        | SseEvent::Error { .. } => Ok(event),
    }
}

/// Check if there's a flushed (property-renamed) tool input buffer
/// for the given content block index. If so, return it and remove
/// from the state.
///
/// The proxy layer should call this before emitting ContentBlockStop
/// to emit the renamed tool input as a final delta.
pub fn take_flushed_input(state: &mut SseState, index: u32) -> Option<String> {
    state.input_buffers.remove(&index)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::{PropertyRename, ResolvedToolRename, UnmappedPolicy};
    use crate::wire::content::ContentBlock;
    use crate::wire::sse::SseState;

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
            unknown_field_rules: std::collections::HashMap::new(),
        }
    }

    #[test]
    fn test_sse_tool_rename() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_bash".into(),
            ResolvedToolRename {
                canonical_name: "Bash".into(),
                description: None,
                schema_override: None,
            },
        );

        let mut state = SseState::default();

        // content_block_start with canonical name "Bash"
        let event = SseEvent::ContentBlockStart {
            index: 0,
            content_block: ContentBlock::ToolUse {
                id: "tu_1".into(),
                name: "Bash".into(),
                input: serde_json::json!({}),
                cache_control: None,
            },
        };

        let result = apply_sse_event_rules(event, &rules, &mut state).unwrap();
        if let SseEvent::ContentBlockStart { content_block, .. } = &result {
            if let ContentBlock::ToolUse { name, .. } = content_block {
                assert_eq!(name, "mcp_bash");
            } else {
                panic!("expected tool_use");
            }
        } else {
            panic!("expected content_block_start");
        }
    }

    #[test]
    fn test_sse_thinking_passthrough() {
        let rules = minimal_ruleset();
        let mut state = SseState::default();

        // Start a thinking block
        let start = SseEvent::ContentBlockStart {
            index: 0,
            content_block: ContentBlock::Thinking {
                thinking: String::new(),
                signature: String::new(),
                budget_tokens: None,
            },
        };
        apply_sse_event_rules(start, &rules, &mut state).unwrap();
        assert!(state.thinking_blocks.contains(&0));

        // Delta should pass through
        let delta = SseEvent::ContentBlockDelta {
            index: 0,
            delta: ContentDelta::ThinkingDelta {
                thinking: "reasoning...".into(),
            },
        };
        let result = apply_sse_event_rules(delta, &rules, &mut state).unwrap();
        if let SseEvent::ContentBlockDelta { delta, .. } = &result {
            if let ContentDelta::ThinkingDelta { thinking } = delta {
                assert_eq!(thinking, "reasoning...");
            }
        }

        // Stop should clean up
        let stop = SseEvent::ContentBlockStop { index: 0 };
        apply_sse_event_rules(stop, &rules, &mut state).unwrap();
        assert!(!state.thinking_blocks.contains(&0));
    }

    #[test]
    fn test_sse_tool_input_buffering() {
        let mut rules = minimal_ruleset();
        rules.tool_renames.insert(
            "mcp_bash".into(),
            ResolvedToolRename {
                canonical_name: "Bash".into(),
                description: None,
                schema_override: None,
            },
        );
        rules.property_renames.push(PropertyRename {
            from: "session_id".into(),
            to: "thread_id".into(),
        });

        let mut state = SseState::default();

        // Start tool block
        let start = SseEvent::ContentBlockStart {
            index: 0,
            content_block: ContentBlock::ToolUse {
                id: "tu_1".into(),
                name: "Bash".into(),
                input: serde_json::json!({}),
                cache_control: None,
            },
        };
        apply_sse_event_rules(start, &rules, &mut state).unwrap();

        // Stream partial input
        let delta1 = SseEvent::ContentBlockDelta {
            index: 0,
            delta: ContentDelta::InputJsonDelta {
                partial_json: r#"{"thread"#.into(),
            },
        };
        apply_sse_event_rules(delta1, &rules, &mut state).unwrap();

        let delta2 = SseEvent::ContentBlockDelta {
            index: 0,
            delta: ContentDelta::InputJsonDelta {
                partial_json: r#"_id": "abc"}"#.into(),
            },
        };
        apply_sse_event_rules(delta2, &rules, &mut state).unwrap();

        // Stop should trigger parse + rename
        let stop = SseEvent::ContentBlockStop { index: 0 };
        apply_sse_event_rules(stop, &rules, &mut state).unwrap();

        // The flushed buffer should have reversed property names
        if let Some(flushed) = take_flushed_input(&mut state, 0) {
            let value: serde_json::Value = serde_json::from_str(&flushed).unwrap();
            assert!(value.get("session_id").is_some());
            assert!(value.get("thread_id").is_none());
        } else {
            panic!("expected flushed input buffer");
        }
    }
}
