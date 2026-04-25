use serde::{Deserialize, Serialize};

use super::content::ContentBlock;

/// Token usage information.
///
/// Unknown fields (e.g. `server_tool_use`) are captured in `extra`
/// so they are preserved when forwarding to the client.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Usage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_creation_input_tokens: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_read_input_tokens: Option<u32>,
    #[serde(flatten, default, skip_serializing_if = "serde_json::Map::is_empty")]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// The top-level Messages API response body.
///
/// Unknown fields are captured in `extra` so new API features
/// are forwarded to the client without data loss.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct MessagesResponse {
    pub id: String,
    #[serde(rename = "type")]
    pub response_type: String,
    pub role: String,
    pub content: Vec<ContentBlock>,
    pub model: String,
    pub stop_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stop_sequence: Option<String>,
    pub usage: Usage,
    #[serde(flatten, default, skip_serializing_if = "serde_json::Map::is_empty")]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// An API error response.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct ApiError {
    #[serde(rename = "type")]
    pub error_type: String,
    pub message: String,
}

/// Wrapper for error responses from the API.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct ApiErrorResponse {
    #[serde(rename = "type")]
    pub response_type: String,
    pub error: ApiError,
}
