use serde::{Deserialize, Serialize};

use super::content::ContentBlock;
use super::response::{ApiError, MessagesResponse};

/// Delta types for streaming content blocks.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum ContentDelta {
    #[serde(rename = "text_delta")]
    TextDelta { text: String },
    #[serde(rename = "input_json_delta")]
    InputJsonDelta { partial_json: String },
    #[serde(rename = "thinking_delta")]
    ThinkingDelta { thinking: String },
    #[serde(rename = "signature_delta")]
    SignatureDelta { signature: String },
}

/// Message delta payload (sent near end of stream).
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct MessageDeltaPayload {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stop_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stop_sequence: Option<String>,
}

/// Usage info sent with message_delta events.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct MessageDeltaUsage {
    pub output_tokens: u32,
}

/// A typed SSE event from the Messages API streaming response.
///
/// Each variant corresponds to an SSE `event:` type. The data payload
/// is deserialized into the variant's fields.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum SseEvent {
    #[serde(rename = "message_start")]
    MessageStart { message: MessagesResponse },

    #[serde(rename = "content_block_start")]
    ContentBlockStart {
        index: u32,
        content_block: ContentBlock,
    },

    #[serde(rename = "content_block_delta")]
    ContentBlockDelta { index: u32, delta: ContentDelta },

    #[serde(rename = "content_block_stop")]
    ContentBlockStop { index: u32 },

    #[serde(rename = "message_delta")]
    MessageDelta {
        delta: MessageDeltaPayload,
        #[serde(skip_serializing_if = "Option::is_none")]
        usage: Option<MessageDeltaUsage>,
    },

    #[serde(rename = "message_stop")]
    MessageStop {},

    #[serde(rename = "ping")]
    Ping {},

    #[serde(rename = "error")]
    Error { error: ApiError },
}

/// State maintained across SSE events during a single streaming response.
///
/// Tracks which content block indices are thinking blocks (passthrough),
/// which tool_use blocks map to which client-side names, and buffers
/// partial tool input JSON for property renaming.
#[derive(Debug, Default)]
pub struct SseState {
    /// Maps content block index → true if it's a thinking block (passthrough).
    pub thinking_blocks: std::collections::HashSet<u32>,

    /// Maps content block index → original client tool name (before forward rename).
    /// Used to reverse-rename tool_use blocks in the response stream.
    pub tool_name_map: std::collections::HashMap<u32, String>,

    /// Maps content block index → tool_use ID from content_block_start.
    pub tool_id_map: std::collections::HashMap<u32, String>,

    /// Buffers partial JSON for tool input deltas, keyed by content block index.
    /// Accumulated until content_block_stop, then parsed and property-renamed.
    pub input_buffers: std::collections::HashMap<u32, String>,
}
