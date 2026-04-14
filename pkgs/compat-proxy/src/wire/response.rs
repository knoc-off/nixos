use serde::{Deserialize, Serialize};

use super::content::ContentBlock;

/// Token usage information.
#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct Usage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_creation_input_tokens: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_read_input_tokens: Option<u32>,
}

/// The top-level Messages API response body.
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
