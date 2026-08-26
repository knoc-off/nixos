//! HTTP layer: Axum handlers and upstream forwarding.
//!
//! The response path is deliberately opaque. Nothing here parses what
//! upstream sends back — the body is streamed through byte for byte, so
//! new event types and response fields need no changes on our side.

use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, HeaderName, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::Value;

use crate::config::{AppState, REQUIRED_OAUTH_BETAS};
use crate::creds::CredentialError;
use crate::shape;

/// Unified proxy error type.
#[derive(Debug, thiserror::Error)]
pub enum ProxyError {
    #[error("credential error: {0}")]
    Credential(#[from] CredentialError),

    #[error("upstream request failed: {0}")]
    Upstream(String),

    #[error("invalid request body: {0}")]
    Deserialize(String),
}

impl IntoResponse for ProxyError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            ProxyError::Credential(CredentialError::Missing(path, _)) => (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("credentials not found at {path}. Run your provider's auth command."),
            ),
            ProxyError::Credential(CredentialError::Expired(path)) => (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("token expired at {path}. Run your provider's auth command to refresh."),
            ),
            ProxyError::Deserialize(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            _ => (StatusCode::BAD_GATEWAY, self.to_string()),
        };

        tracing::error!(%status, error = %self, "proxy error");

        let body = serde_json::json!({
            "type": "error",
            "error": { "type": "proxy_error", "message": message },
        });

        (status, Json(body)).into_response()
    }
}

/// Health check endpoint.
pub async fn health() -> &'static str {
    "ok"
}

/// Rate-limit usage endpoint — returns cached utilization from upstream headers.
pub async fn handle_usage(State(state): State<AppState>) -> impl IntoResponse {
    Json(state.usage.snapshot())
}

/// Response headers worth passing back to the client. Hop-by-hop headers
/// and anything describing the upstream transfer encoding are dropped —
/// axum re-frames the body itself, so forwarding those would misdescribe it.
const FORWARDED_RESPONSE_HEADERS: &[&str] = &[
    "content-type",
    "cache-control",
    "anthropic-ratelimit-unified-status",
    "anthropic-ratelimit-unified-reset",
    "request-id",
];

/// Build Stainless SDK headers matching real Claude Code's Anthropic JS SDK.
fn stainless_headers(cc_version: &str, session_id: &str) -> Vec<(&'static str, String)> {
    let os_name = if cfg!(target_os = "macos") {
        "macOS"
    } else if cfg!(target_os = "windows") {
        "Windows"
    } else {
        "Linux"
    };
    let arch = if cfg!(target_arch = "x86_64") {
        "x64"
    } else if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        std::env::consts::ARCH
    };

    vec![
        ("user-agent", format!("claude-cli/{cc_version} (third-party, cli)")),
        ("x-app", "cli".to_string()),
        ("x-claude-code-session-id", session_id.to_string()),
        ("x-stainless-arch", arch.to_string()),
        ("x-stainless-lang", "js".to_string()),
        ("x-stainless-os", os_name.to_string()),
        ("x-stainless-package-version", "0.81.0".to_string()),
        ("x-stainless-runtime", "node".to_string()),
        ("x-stainless-runtime-version", "v22.14.0".to_string()),
        ("x-stainless-retry-count", "0".to_string()),
        ("x-stainless-timeout", "600".to_string()),
        ("anthropic-dangerous-direct-browser-access", "true".to_string()),
    ]
}

/// Build the anthropic-beta header value, merging required OAuth betas
/// with any user-configured betas.
fn build_beta_header(user_betas: Option<&str>, is_oauth: bool) -> String {
    let mut betas: Vec<String> = user_betas
        .into_iter()
        .flat_map(|list| list.split(','))
        .map(str::trim)
        .filter(|b| !b.is_empty())
        .map(str::to_string)
        .collect();

    if is_oauth {
        for required in REQUIRED_OAUTH_BETAS {
            if !betas.iter().any(|b| b == required) {
                betas.push((*required).to_string());
            }
        }
    }

    betas.join(",")
}

/// Handler for `POST /v1/messages`.
pub async fn handle_messages(
    State(state): State<AppState>,
    body: axum::body::Bytes,
) -> Result<Response, ProxyError> {
    let mut req: Value = serde_json::from_slice(&body).map_err(|e| {
        tracing::error!(error = %e, body_len = body.len(), "failed to parse request body");
        ProxyError::Deserialize(e.to_string())
    })?;

    shape::to_claude_code(
        &mut req,
        &shape::Context {
            cc_version: &state.cc_version,
            session_id: &state.session_id,
            device_id: &state.device_id,
            max_tokens: Some(state.max_tokens),
        },
    );

    // Read credentials fresh — Claude Code rewrites this file on refresh,
    // so anything cached here goes stale without warning.
    let cred = state.creds.read_credential()?;

    let mut upstream = state
        .client
        .post(format!("{}/v1/messages", state.upstream_url))
        .header("anthropic-version", &state.api_version)
        .header("content-type", "application/json");

    if cred.is_oauth {
        upstream = upstream.header("authorization", format!("Bearer {}", cred.token));
    } else {
        upstream = upstream.header("x-api-key", &cred.token);
    }

    let betas = build_beta_header(state.betas.as_deref(), cred.is_oauth);
    if !betas.is_empty() {
        upstream = upstream.header("anthropic-beta", betas);
    }

    for (name, value) in stainless_headers(&state.cc_version, &state.session_id) {
        upstream = upstream.header(name, value);
    }

    let body = serde_json::to_vec(&req).map_err(|e| ProxyError::Upstream(e.to_string()))?;
    let resp = upstream
        .body(body)
        .send()
        .await
        .map_err(|e| ProxyError::Upstream(e.to_string()))?;

    state.usage.update_from_headers(resp.headers());

    let status = resp.status();
    if !status.is_success() {
        tracing::warn!(status = status.as_u16(), "upstream returned an error");
    }

    let mut headers = HeaderMap::new();
    for name in FORWARDED_RESPONSE_HEADERS {
        if let Some(value) = resp.headers().get(*name) {
            if let Ok(name) = HeaderName::try_from(*name) {
                headers.insert(name, value.clone());
            }
        }
    }

    // Stream the body straight through. Errors mid-stream surface as a
    // truncated body, which is what the client would see from upstream
    // directly, so there is nothing useful to translate here.
    Ok((status, headers, Body::from_stream(resp.bytes_stream())).into_response())
}

/// Fallback handler — logs unmatched requests so we can see what clients are hitting.
async fn fallback(req: axum::extract::Request) -> impl IntoResponse {
    tracing::warn!(method = %req.method(), uri = %req.uri(), "unmatched route");
    (StatusCode::NOT_FOUND, "Not Found")
}

/// Build the Axum router with all routes.
pub fn build_router(state: AppState) -> axum::Router {
    axum::Router::new()
        .route("/v1/messages", axum::routing::post(handle_messages))
        .route("/v1/usage", axum::routing::get(handle_usage))
        .route("/health", axum::routing::get(health))
        .fallback(fallback)
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn oauth_betas_are_added_and_deduplicated() {
        let header = build_beta_header(Some("oauth-2025-04-20, custom-beta"), true);
        let betas: Vec<&str> = header.split(',').collect();

        assert_eq!(betas[0], "oauth-2025-04-20");
        assert_eq!(betas[1], "custom-beta");
        assert_eq!(betas.iter().filter(|b| **b == "oauth-2025-04-20").count(), 1);
        for required in REQUIRED_OAUTH_BETAS {
            assert!(betas.contains(required), "missing {required}");
        }
    }

    #[test]
    fn api_key_auth_gets_no_oauth_betas() {
        assert_eq!(build_beta_header(None, false), "");
        assert_eq!(build_beta_header(Some("custom"), false), "custom");
    }
}
