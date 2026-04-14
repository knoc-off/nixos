use serde::{Deserialize, Serialize};

/// Opaque wrapper around thinking block data.
///
/// Implements Serialize/Deserialize but exposes no mutation API.
/// The API enforces byte-equality on thinking blocks across turns;
/// making mutation impossible at the type level eliminates the entire
/// class of "thinking blocks cannot be modified" errors.
#[derive(Debug, Clone)]
pub struct ThinkingBlock(serde_json::Value);

impl ThinkingBlock {
    /// Read-only access to the inner value for serialization/inspection.
    pub fn as_value(&self) -> &serde_json::Value {
        &self.0
    }
}

impl Serialize for ThinkingBlock {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for ThinkingBlock {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        serde_json::Value::deserialize(deserializer).map(ThinkingBlock)
    }
}

/// Cache control annotation on content blocks.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct CacheControl {
    #[serde(rename = "type")]
    pub cache_type: String,
}

/// Source for an image content block.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct ImageSource {
    #[serde(rename = "type")]
    pub source_type: String,
    pub media_type: String,
    pub data: String,
}

/// Content of a tool result — can be a simple string or structured blocks.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(untagged)]
pub enum ToolResultContent {
    String(String),
    Blocks(Vec<ToolResultBlock>),
}

/// A single block within a tool result's content array.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum ToolResultBlock {
    #[serde(rename = "text")]
    Text {
        text: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
    #[serde(rename = "image")]
    Image {
        source: ImageSource,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
}

/// A single content block in a message.
#[derive(Deserialize, Serialize, Debug, Clone)]
#[serde(tag = "type")]
pub enum ContentBlock {
    #[serde(rename = "text")]
    Text {
        text: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
    #[serde(rename = "tool_use")]
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
    #[serde(rename = "tool_result")]
    ToolResult {
        tool_use_id: String,
        content: ToolResultContent,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        is_error: Option<bool>,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
    #[serde(rename = "thinking")]
    Thinking {
        thinking: String,
        signature: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        budget_tokens: Option<u32>,
    },
    #[serde(rename = "redacted_thinking")]
    RedactedThinking {
        data: String,
    },
    #[serde(rename = "image")]
    Image {
        source: ImageSource,
        #[serde(skip_serializing_if = "Option::is_none")]
        cache_control: Option<CacheControl>,
    },
}

impl ContentBlock {
    /// Returns the tool name if this is a ToolUse block.
    pub fn tool_use_name(&self) -> Option<&str> {
        match self {
            ContentBlock::ToolUse { name, .. } => Some(name),
            _ => None,
        }
    }

    /// Returns the tool_use_id if this is a ToolResult block.
    pub fn tool_result_id(&self) -> Option<&str> {
        match self {
            ContentBlock::ToolResult { tool_use_id, .. } => Some(tool_use_id),
            _ => None,
        }
    }

    /// Returns true if this is a thinking or redacted_thinking block.
    pub fn is_thinking(&self) -> bool {
        matches!(self, ContentBlock::Thinking { .. } | ContentBlock::RedactedThinking { .. })
    }
}
