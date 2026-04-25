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
pub struct CacheControl {
    #[serde(rename = "type")]
    pub cache_type: String,
    /// TTL hint (e.g. "1h", "5m"). Added in newer API versions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ttl: Option<String>,
}

/// Source for an image content block.
#[derive(Deserialize, Serialize, Debug, Clone)]
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
///
/// Uses custom Deserialize/Serialize so that unknown block types (e.g.
/// future Anthropic additions like `document`, `citation`, `mcp_tool_use`)
/// are captured as `Other(Value)` instead of causing a hard deserialization
/// failure. This is critical for a proxy that must forward data it doesn't
/// fully understand.
#[derive(Debug, Clone)]
pub enum ContentBlock {
    Text {
        text: String,
        cache_control: Option<CacheControl>,
    },
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
        cache_control: Option<CacheControl>,
    },
    ToolResult {
        tool_use_id: String,
        content: ToolResultContent,
        is_error: Option<bool>,
        cache_control: Option<CacheControl>,
    },
    Thinking {
        thinking: String,
        signature: String,
        budget_tokens: Option<u32>,
    },
    RedactedThinking {
        data: String,
    },
    Image {
        source: ImageSource,
        cache_control: Option<CacheControl>,
    },
    /// Server-initiated tool use (e.g. web_search). Must be preserved
    /// verbatim and passed back in multi-turn conversations.
    ServerToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
    },
    /// Result from a server-initiated tool (e.g. web search results).
    /// Contains structured content that must be passed back verbatim.
    WebSearchToolResult {
        tool_use_id: String,
        content: serde_json::Value,
    },
    /// Catch-all for unrecognized block types. Preserves the full JSON
    /// value so new Anthropic features don't break the proxy and can be
    /// round-tripped without data loss.
    Other(serde_json::Value),
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
        matches!(
            self,
            ContentBlock::Thinking { .. } | ContentBlock::RedactedThinking { .. }
        )
    }

    /// Returns true if this is a server-side tool block.
    pub fn is_server_tool(&self) -> bool {
        matches!(
            self,
            ContentBlock::ServerToolUse { .. } | ContentBlock::WebSearchToolResult { .. }
        )
    }

    /// Returns true if this block should be passed through without
    /// any transformation — thinking blocks, server tool blocks,
    /// and unknown block types.
    pub fn is_passthrough(&self) -> bool {
        self.is_thinking() || self.is_server_tool() || matches!(self, ContentBlock::Other(_))
    }
}

// ---------------------------------------------------------------------------
// Custom Deserialize
// ---------------------------------------------------------------------------

impl<'de> Deserialize<'de> for ContentBlock {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = serde_json::Value::deserialize(deserializer)?;

        let block_type = value
            .get("type")
            .and_then(|t| t.as_str())
            .unwrap_or("");

        match block_type {
            "text" => {
                let text = value
                    .get("text")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| serde::de::Error::missing_field("text"))?
                    .to_string();
                let cache_control = deser_opt::<CacheControl, D>(&value, "cache_control")?;
                Ok(ContentBlock::Text {
                    text,
                    cache_control,
                })
            }

            "tool_use" => {
                let id = require_str::<D>(&value, "id")?;
                let name = require_str::<D>(&value, "name")?;
                let input = value
                    .get("input")
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                let cache_control = deser_opt::<CacheControl, D>(&value, "cache_control")?;
                Ok(ContentBlock::ToolUse {
                    id,
                    name,
                    input,
                    cache_control,
                })
            }

            "tool_result" => {
                let tool_use_id = require_str::<D>(&value, "tool_use_id")?;
                let content: ToolResultContent = value
                    .get("content")
                    .cloned()
                    .map(|v| {
                        serde_json::from_value(v).map_err(serde::de::Error::custom)
                    })
                    .transpose()?
                    // Default to empty string if content field is absent
                    .unwrap_or(ToolResultContent::String(String::new()));
                let is_error = value.get("is_error").and_then(|v| v.as_bool());
                let cache_control = deser_opt::<CacheControl, D>(&value, "cache_control")?;
                Ok(ContentBlock::ToolResult {
                    tool_use_id,
                    content,
                    is_error,
                    cache_control,
                })
            }

            "thinking" => {
                let thinking = require_str::<D>(&value, "thinking")?;
                let signature = require_str::<D>(&value, "signature")?;
                let budget_tokens = value
                    .get("budget_tokens")
                    .and_then(|v| v.as_u64())
                    .map(|v| v as u32);
                Ok(ContentBlock::Thinking {
                    thinking,
                    signature,
                    budget_tokens,
                })
            }

            "redacted_thinking" => {
                let data = require_str::<D>(&value, "data")?;
                Ok(ContentBlock::RedactedThinking { data })
            }

            "image" => {
                let source: ImageSource = value
                    .get("source")
                    .cloned()
                    .ok_or_else(|| serde::de::Error::missing_field("source"))
                    .and_then(|v| serde_json::from_value(v).map_err(serde::de::Error::custom))?;
                let cache_control = deser_opt::<CacheControl, D>(&value, "cache_control")?;
                Ok(ContentBlock::Image {
                    source,
                    cache_control,
                })
            }

            "server_tool_use" => {
                let id = require_str::<D>(&value, "id")?;
                let name = require_str::<D>(&value, "name")?;
                let input = value
                    .get("input")
                    .cloned()
                    .unwrap_or(serde_json::json!({}));
                Ok(ContentBlock::ServerToolUse { id, name, input })
            }

            "web_search_tool_result" => {
                let tool_use_id = require_str::<D>(&value, "tool_use_id")?;
                let content = value
                    .get("content")
                    .cloned()
                    .unwrap_or(serde_json::json!([]));
                Ok(ContentBlock::WebSearchToolResult {
                    tool_use_id,
                    content,
                })
            }

            other => {
                tracing::debug!(
                    block_type = other,
                    "unrecognized content block type, preserving as Other"
                );
                Ok(ContentBlock::Other(value))
            }
        }
    }
}

/// Helper: extract a required string field or return a missing-field error.
fn require_str<'de, D: serde::Deserializer<'de>>(
    value: &serde_json::Value,
    field: &'static str,
) -> Result<String, D::Error> {
    value
        .get(field)
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| serde::de::Error::missing_field(field))
}

/// Helper: optionally deserialize a nested field via serde_json::from_value.
fn deser_opt<'de, T, D>(
    value: &serde_json::Value,
    field: &str,
) -> Result<Option<T>, D::Error>
where
    T: serde::de::DeserializeOwned,
    D: serde::Deserializer<'de>,
{
    match value.get(field) {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(v) => serde_json::from_value(v.clone())
            .map(Some)
            .map_err(serde::de::Error::custom),
    }
}

// ---------------------------------------------------------------------------
// Custom Serialize
// ---------------------------------------------------------------------------

impl Serialize for ContentBlock {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde_json::{Map, Value};

        match self {
            ContentBlock::Text {
                text,
                cache_control,
            } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("text".into()));
                map.insert("text".into(), Value::String(text.clone()));
                insert_cache_control(&mut map, cache_control);
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::ToolUse {
                id,
                name,
                input,
                cache_control,
            } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("tool_use".into()));
                map.insert("id".into(), Value::String(id.clone()));
                map.insert("name".into(), Value::String(name.clone()));
                map.insert("input".into(), input.clone());
                insert_cache_control(&mut map, cache_control);
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::ToolResult {
                tool_use_id,
                content,
                is_error,
                cache_control,
            } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("tool_result".into()));
                map.insert(
                    "tool_use_id".into(),
                    Value::String(tool_use_id.clone()),
                );
                map.insert(
                    "content".into(),
                    serde_json::to_value(content).map_err(serde::ser::Error::custom)?,
                );
                if let Some(err) = is_error {
                    map.insert("is_error".into(), Value::Bool(*err));
                }
                insert_cache_control(&mut map, cache_control);
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::Thinking {
                thinking,
                signature,
                budget_tokens,
            } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("thinking".into()));
                map.insert("thinking".into(), Value::String(thinking.clone()));
                map.insert("signature".into(), Value::String(signature.clone()));
                if let Some(bt) = budget_tokens {
                    map.insert(
                        "budget_tokens".into(),
                        Value::Number((*bt).into()),
                    );
                }
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::RedactedThinking { data } => {
                let mut map = Map::new();
                map.insert(
                    "type".into(),
                    Value::String("redacted_thinking".into()),
                );
                map.insert("data".into(), Value::String(data.clone()));
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::Image {
                source,
                cache_control,
            } => {
                let mut map = Map::new();
                map.insert("type".into(), Value::String("image".into()));
                map.insert(
                    "source".into(),
                    serde_json::to_value(source).map_err(serde::ser::Error::custom)?,
                );
                insert_cache_control(&mut map, cache_control);
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::ServerToolUse { id, name, input } => {
                let mut map = Map::new();
                map.insert(
                    "type".into(),
                    Value::String("server_tool_use".into()),
                );
                map.insert("id".into(), Value::String(id.clone()));
                map.insert("name".into(), Value::String(name.clone()));
                map.insert("input".into(), input.clone());
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::WebSearchToolResult {
                tool_use_id,
                content,
            } => {
                let mut map = Map::new();
                map.insert(
                    "type".into(),
                    Value::String("web_search_tool_result".into()),
                );
                map.insert(
                    "tool_use_id".into(),
                    Value::String(tool_use_id.clone()),
                );
                map.insert("content".into(), content.clone());
                Value::Object(map).serialize(serializer)
            }

            ContentBlock::Other(value) => {
                // Pass through the raw JSON value — it already contains the
                // "type" field and all other data.
                value.serialize(serializer)
            }
        }
    }
}

/// Helper: insert `cache_control` into a JSON map if present.
fn insert_cache_control(
    map: &mut serde_json::Map<String, serde_json::Value>,
    cache_control: &Option<CacheControl>,
) {
    if let Some(cc) = cache_control {
        if let Ok(v) = serde_json::to_value(cc) {
            map.insert("cache_control".into(), v);
        }
    }
}
