use serde::{Deserialize, Serialize};

use super::content::{CacheControl, ContentBlock};

/// The system prompt — either a plain string or an array of typed blocks.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(untagged)]
pub enum SystemPrompt {
    String(String),
    Blocks(Vec<SystemBlock>),
}

impl SystemPrompt {
    /// Extract all text content from the system prompt.
    pub fn text_content(&self) -> String {
        match self {
            SystemPrompt::String(s) => s.clone(),
            SystemPrompt::Blocks(blocks) => blocks
                .iter()
                .filter_map(|b| match b {
                    SystemBlock::Text { text, .. } => Some(text.as_str()),
                })
                .collect::<Vec<_>>()
                .join("\n"),
        }
    }

    /// Convert to block form if not already.
    pub fn into_blocks(self) -> Vec<SystemBlock> {
        match self {
            SystemPrompt::String(s) => vec![SystemBlock::Text {
                text: s,
                cache_control: None,
            }],
            SystemPrompt::Blocks(blocks) => blocks,
        }
    }
}

/// A block within a structured system prompt.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum SystemBlock {
    #[serde(rename = "text")]
    Text {
        text: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
}

/// A tool definition sent in the request.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Tool {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub input_schema: InputSchema,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cache_control: Option<CacheControl>,
}

/// JSON Schema for tool input parameters.
///
/// `additional_properties` is `Option<serde_json::Value>` because in JSON
/// Schema it can be a boolean (`false`) OR a schema object
/// (`{"type": "string"}`, `{"type": "object", "properties": {...}}`).
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct InputSchema {
    #[serde(rename = "type")]
    pub schema_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub properties: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub required: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[serde(rename = "additionalProperties")]
    pub additional_properties: Option<serde_json::Value>,
}

/// Tool choice constraint.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum ToolChoice {
    #[serde(rename = "auto")]
    Auto {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        disable_parallel_tool_use: Option<bool>,
    },
    #[serde(rename = "any")]
    Any {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        disable_parallel_tool_use: Option<bool>,
    },
    #[serde(rename = "tool")]
    Tool {
        name: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        disable_parallel_tool_use: Option<bool>,
    },
    #[serde(rename = "none")]
    None {},
}

/// Request metadata.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Metadata {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<String>,
}

/// A single message in the conversation.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Message {
    pub role: Role,
    pub content: MessageContent,
}

/// Message role.
#[derive(Deserialize, Serialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    User,
    Assistant,
}

/// Message content — either a plain string or structured blocks.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(untagged)]
pub enum MessageContent {
    String(String),
    Blocks(Vec<ContentBlock>),
}

impl MessageContent {
    /// Get content blocks, converting string to a single text block if needed.
    pub fn into_blocks(self) -> Vec<ContentBlock> {
        match self {
            MessageContent::String(s) => vec![ContentBlock::Text {
                text: s,
                cache_control: None,
            }],
            MessageContent::Blocks(blocks) => blocks,
        }
    }

    /// Get a reference to blocks if already in block form.
    pub fn as_blocks(&self) -> Option<&[ContentBlock]> {
        match self {
            MessageContent::Blocks(blocks) => Some(blocks),
            _ => None,
        }
    }
}

/// Thinking configuration for extended thinking.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Thinking {
    #[serde(rename = "type")]
    pub thinking_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub budget_tokens: Option<u32>,
}

/// The top-level Messages API request body.
///
/// Known fields are modeled explicitly. Unknown fields (e.g. `output_config`,
/// `service_tier`, `container`) are captured in `extra` and forwarded to
/// upstream so new API features don't silently break.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct MessagesRequest {
    pub model: String,
    pub max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub system: Option<SystemPrompt>,
    pub messages: Vec<Message>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<Tool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_choice: Option<ToolChoice>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metadata: Option<Metadata>,
    #[serde(default)]
    pub stream: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thinking: Option<Thinking>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub top_k: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stop_sequences: Option<Vec<String>>,
    /// Catch-all for unknown top-level fields. Preserved and forwarded
    /// to upstream. Check logs for warnings about forwarded fields.
    #[serde(flatten, default, skip_serializing_if = "serde_json::Map::is_empty")]
    pub extra: serde_json::Map<String, serde_json::Value>,
}
