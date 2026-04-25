use serde::{Deserialize, Serialize};

use super::content::ContentBlock;
use super::response::{ApiError, MessagesResponse};

/// Delta types for streaming content blocks.
///
/// Uses custom Deserialize so unknown delta types (e.g. future Anthropic
/// additions) are captured as `Other(Value)` instead of breaking the stream.
#[derive(Debug, Clone)]
pub enum ContentDelta {
    TextDelta { text: String },
    InputJsonDelta { partial_json: String },
    ThinkingDelta { thinking: String },
    SignatureDelta { signature: String },
    CitationsDelta { citation: serde_json::Value },
    /// Catch-all for unrecognized delta types.
    Other(serde_json::Value),
}

impl<'de> Deserialize<'de> for ContentDelta {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = serde_json::Value::deserialize(deserializer)?;
        let delta_type = value
            .get("type")
            .and_then(|t| t.as_str())
            .unwrap_or("");

        match delta_type {
            "text_delta" => {
                let text = value
                    .get("text")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| serde::de::Error::missing_field("text"))?
                    .to_string();
                Ok(ContentDelta::TextDelta { text })
            }
            "input_json_delta" => {
                let partial_json = value
                    .get("partial_json")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| serde::de::Error::missing_field("partial_json"))?
                    .to_string();
                Ok(ContentDelta::InputJsonDelta { partial_json })
            }
            "thinking_delta" => {
                let thinking = value
                    .get("thinking")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| serde::de::Error::missing_field("thinking"))?
                    .to_string();
                Ok(ContentDelta::ThinkingDelta { thinking })
            }
            "signature_delta" => {
                let signature = value
                    .get("signature")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| serde::de::Error::missing_field("signature"))?
                    .to_string();
                Ok(ContentDelta::SignatureDelta { signature })
            }
            "citations_delta" => {
                let citation = value
                    .get("citation")
                    .cloned()
                    .unwrap_or(serde_json::json!(null));
                Ok(ContentDelta::CitationsDelta { citation })
            }
            _other => {
                tracing::debug!(
                    delta_type = _other,
                    "unrecognized content delta type, preserving as Other"
                );
                Ok(ContentDelta::Other(value))
            }
        }
    }
}

impl Serialize for ContentDelta {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde_json::{Map, Value};

        match self {
            ContentDelta::TextDelta { text } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("text_delta".into()));
                map.insert("text".into(), Value::String(text.clone()));
                Value::Object(map).serialize(serializer)
            }
            ContentDelta::InputJsonDelta { partial_json } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("input_json_delta".into()));
                map.insert(
                    "partial_json".into(),
                    Value::String(partial_json.clone()),
                );
                Value::Object(map).serialize(serializer)
            }
            ContentDelta::ThinkingDelta { thinking } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("thinking_delta".into()));
                map.insert("thinking".into(), Value::String(thinking.clone()));
                Value::Object(map).serialize(serializer)
            }
            ContentDelta::SignatureDelta { signature } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("signature_delta".into()));
                map.insert("signature".into(), Value::String(signature.clone()));
                Value::Object(map).serialize(serializer)
            }
            ContentDelta::CitationsDelta { citation } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("citations_delta".into()));
                map.insert("citation".into(), citation.clone());
                Value::Object(map).serialize(serializer)
            }
            ContentDelta::Other(value) => value.serialize(serializer),
        }
    }
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
