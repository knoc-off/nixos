//! HTTP layer: Axum handlers, upstream forwarding, SSE streaming.

use std::convert::Infallible;

use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::Json;
use futures_util::stream::Stream;
use futures_util::StreamExt;
use tokio_stream::wrappers::ReceiverStream;

use crate::config::{AppState, REQUIRED_OAUTH_BETAS};
use crate::creds::CredentialError;
use crate::rules::apply_sse::take_flushed_input;
use crate::rules::{apply_request_rules, apply_response_rules, apply_sse_event_rules, RuleError};
use crate::wire::request::MessagesRequest;
use crate::wire::response::MessagesResponse;
use crate::wire::sse::{ContentDelta, SseEvent, SseState};

/// Unified proxy error type.
#[derive(Debug, thiserror::Error)]
pub enum ProxyError {
    #[error("rule error: {0}")]
    Rule(#[from] RuleError),

    #[error("credential error: {0}")]
    Credential(#[from] CredentialError),

    #[error("upstream request failed: {0}")]
    Upstream(String),

    #[error("upstream returned {0}: {1}")]
    UpstreamStatus(u16, String),

    #[error("deserialization error: {0}")]
    Deserialize(String),

    #[error("internal error: {0}")]
    Internal(String),
}

impl IntoResponse for ProxyError {
    fn into_response(self) -> Response {
        let (status, message) = match &self {
            ProxyError::Rule(RuleError::UnmappedTool(name)) => (
                StatusCode::BAD_REQUEST,
                format!("unmapped tool: {name}. Add a rename or drop rule for this tool."),
            ),
            ProxyError::Credential(CredentialError::Missing(path, _)) => (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("credentials not found at {path}. Run your provider's auth command."),
            ),
            ProxyError::Credential(CredentialError::Expired(path)) => (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("token expired at {path}. Run your provider's auth command to refresh."),
            ),
            ProxyError::UpstreamStatus(code, body) => {
                let status = StatusCode::from_u16(*code).unwrap_or(StatusCode::BAD_GATEWAY);
                (status, body.clone())
            }
            _ => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
        };

        tracing::error!(%status, error = %self, "proxy error");

        let error_body = serde_json::json!({
            "type": "error",
            "error": {
                "type": "proxy_error",
                "message": message
            }
        });

        (status, Json(error_body)).into_response()
    }
}

/// Health check endpoint.
pub async fn health() -> &'static str {
    "ok"
}

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
    let mut betas: Vec<String> = Vec::new();

    // Add user-configured betas first
    if let Some(user) = user_betas {
        for b in user.split(',') {
            let trimmed = b.trim().to_string();
            if !trimmed.is_empty() {
                betas.push(trimmed);
            }
        }
    }

    // For OAuth tokens, ensure all required betas are present
    if is_oauth {
        for required in REQUIRED_OAUTH_BETAS {
            let req = required.to_string();
            if !betas.contains(&req) {
                betas.push(req);
            }
        }
    }

    betas.join(",")
}

/// Main proxy handler for POST /v1/messages.
///
/// Accepts raw bytes first so we can dump the body even when
/// deserialization fails (critical for debugging new block types).
pub async fn handle_messages(
    State(state): State<AppState>,
    _headers: HeaderMap,
    body: axum::body::Bytes,
) -> Result<Response, ProxyError> {
    let rules = state.rules.load_full(); // Arc<RuleSet>

    // Always dump raw bytes BEFORE deserialization so we capture
    // the exact payload even when parsing fails.
    if state.dump_requests {
        let path = std::env::temp_dir().join(format!(
            "proxy-raw-{}.json",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        ));
        if let Err(e) = std::fs::write(&path, &body) {
            tracing::warn!("failed to dump raw request: {e}");
        } else {
            tracing::debug!("dumped raw request to {} ({} bytes)", path.display(), body.len());
        }
    }

    // Deserialize — now failures are debuggable via the raw dump above.
    let req: MessagesRequest = serde_json::from_slice(&body).map_err(|e| {
        tracing::error!(
            error = %e,
            body_len = body.len(),
            "failed to deserialize request body"
        );
        ProxyError::Deserialize(format!("{e}"))
    })?;

    let wants_stream = req.stream;

    // Log the parsed (pre-translation) request if debugging
    if state.dump_requests {
        if let Ok(json) = serde_json::to_string_pretty(&req) {
            let path = std::env::temp_dir().join(format!(
                "proxy-req-{}.json",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis()
            ));
            if let Err(e) = std::fs::write(&path, &json) {
                tracing::warn!("failed to dump request: {e}");
            } else {
                tracing::debug!("dumped parsed request to {}", path.display());
            }
        }
    }

    // Forward translation (includes billing fingerprint injection)
    let translated = apply_request_rules(req, &rules, &state.session_id, &state.device_id)?;

    // Read credentials fresh
    let cred = state.creds.read_credential()?;

    // Build upstream request
    let upstream_url = format!("{}/v1/messages", state.upstream_url);

    let mut upstream_req = state.client.post(&upstream_url);

    // Auth header: OAuth uses Bearer, API keys use x-api-key
    if cred.is_oauth {
        upstream_req = upstream_req.header("authorization", format!("Bearer {}", cred.token));
    } else {
        upstream_req = upstream_req.header("x-api-key", &cred.token);
    }

    // Core headers
    upstream_req = upstream_req
        .header("anthropic-version", &state.api_version)
        .header("content-type", "application/json");

    // Beta flags (merges user betas + required OAuth betas)
    let beta_header = build_beta_header(state.betas.as_deref(), cred.is_oauth);
    if !beta_header.is_empty() {
        upstream_req = upstream_req.header("anthropic-beta", &beta_header);
    }

    // Stainless SDK headers (mimic real Claude Code's JS SDK fingerprint)
    for (name, value) in stainless_headers(&rules.cc_version, &state.session_id) {
        upstream_req = upstream_req.header(name, value);
    }

    // Inject additional headers from rules (these can override stainless headers)
    for header in &rules.headers {
        upstream_req = upstream_req.header(&header.name, &header.value);
    }

    // Send the translated request body
    let body = serde_json::to_vec(&translated)
        .map_err(|e| ProxyError::Internal(format!("failed to serialize request: {e}")))?;

    if state.dump_requests {
        let path = std::env::temp_dir().join(format!(
            "proxy-translated-{}.json",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis()
        ));
        let _ = std::fs::write(&path, &body);
        tracing::debug!("dumped translated request to {}", path.display());
    }

    let upstream_resp = upstream_req
        .body(body)
        .send()
        .await
        .map_err(|e| ProxyError::Upstream(e.to_string()))?;

    let status = upstream_resp.status();

    // If upstream returned an error, forward it
    if !status.is_success() {
        let body = upstream_resp
            .text()
            .await
            .unwrap_or_else(|_| "failed to read error body".into());
        return Err(ProxyError::UpstreamStatus(status.as_u16(), body));
    }

    if wants_stream {
        // SSE streaming response
        let stream = create_sse_stream(upstream_resp, rules.clone());
        Ok(Sse::new(stream)
            .keep_alive(KeepAlive::default())
            .into_response())
    } else {
        // JSON response
        let resp_body = upstream_resp
            .text()
            .await
            .map_err(|e| ProxyError::Upstream(format!("failed to read response: {e}")))?;

        if state.dump_requests {
            let path = std::env::temp_dir().join(format!(
                "proxy-resp-{}.json",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_millis()
            ));
            let _ = std::fs::write(&path, &resp_body);
        }

        let resp: MessagesResponse = serde_json::from_str(&resp_body)
            .map_err(|e| ProxyError::Deserialize(format!("{e}: {resp_body}")))?;

        let translated_resp = apply_response_rules(resp, &rules)?;
        Ok(Json(translated_resp).into_response())
    }
}

/// Create an SSE stream that reads from the upstream response,
/// applies reverse translation rules, and emits events to the client.
fn create_sse_stream(
    upstream_resp: reqwest::Response,
    rules: std::sync::Arc<crate::rules::RuleSet>,
) -> impl Stream<Item = Result<Event, Infallible>> {
    let (tx, rx) = tokio::sync::mpsc::channel::<Result<Event, Infallible>>(64);

    tokio::spawn(async move {
        let mut state = SseState::default();
        let mut bytes_stream = upstream_resp.bytes_stream();
        let mut line_buffer = String::new();
        let mut current_event_type = String::new();
        let mut current_data = String::new();

        while let Some(chunk_result) = bytes_stream.next().await {
            let chunk = match chunk_result {
                Ok(c) => c,
                Err(e) => {
                    tracing::error!("upstream stream error: {e}");
                    break;
                }
            };

            let chunk_str = match std::str::from_utf8(&chunk) {
                Ok(s) => s,
                Err(e) => {
                    tracing::error!("upstream sent invalid UTF-8: {e}");
                    break;
                }
            };

            line_buffer.push_str(chunk_str);

            // Process complete lines from the buffer
            while let Some(newline_pos) = line_buffer.find('\n') {
                let line = line_buffer[..newline_pos]
                    .trim_end_matches('\r')
                    .to_string();
                line_buffer = line_buffer[newline_pos + 1..].to_string();

                if line.is_empty() {
                    // Empty line = end of event
                    if !current_data.is_empty() {
                        let event = process_sse_event(
                            &current_event_type,
                            &current_data,
                            &rules,
                            &mut state,
                        );

                        match event {
                            Ok(Some(sse_events)) => {
                                for sse_event in sse_events {
                                    if tx.send(Ok(sse_event)).await.is_err() {
                                        return; // Client disconnected
                                    }
                                }
                            }
                            Ok(None) => {} // Event was filtered/suppressed
                            Err(e) => {
                                tracing::error!("SSE translation error: {e}");
                                let error_event = Event::default()
                                    .event("error")
                                    .data(format!(
                                        r#"{{"type":"error","error":{{"type":"proxy_error","message":"{e}"}}}}"#
                                    ));
                                let _ = tx.send(Ok(error_event)).await;
                                return;
                            }
                        }
                    }
                    current_event_type.clear();
                    current_data.clear();
                } else if let Some(value) = line.strip_prefix("event: ") {
                    current_event_type = value.to_string();
                } else if let Some(value) = line.strip_prefix("data: ") {
                    if !current_data.is_empty() {
                        current_data.push('\n');
                    }
                    current_data.push_str(value);
                } else if line.starts_with(':') {
                    // Comment line — ignore
                } else if let Some(value) = line.strip_prefix("event:") {
                    current_event_type = value.trim().to_string();
                } else if let Some(value) = line.strip_prefix("data:") {
                    if !current_data.is_empty() {
                        current_data.push('\n');
                    }
                    current_data.push_str(value.trim());
                }
            }
        }
    });

    ReceiverStream::new(rx)
}

/// Process a single SSE event: parse, translate, re-serialize.
fn process_sse_event(
    _event_type: &str,
    data: &str,
    rules: &crate::rules::RuleSet,
    state: &mut SseState,
) -> Result<Option<Vec<Event>>, ProxyError> {
    let sse_event: SseEvent = serde_json::from_str(data)
        .map_err(|e| ProxyError::Deserialize(format!("SSE event parse error: {e}: {data}")))?;

    let translated =
        apply_sse_event_rules(sse_event, rules, state).map_err(ProxyError::Rule)?;

    let mut events = Vec::new();

    // For content_block_stop, check if we need to emit a flushed delta first
    if let SseEvent::ContentBlockStop { index } = &translated {
        if let Some(flushed_json) = take_flushed_input(state, *index) {
            let flush_delta = SseEvent::ContentBlockDelta {
                index: *index,
                delta: ContentDelta::InputJsonDelta {
                    partial_json: flushed_json,
                },
            };
            let flush_data = serde_json::to_string(&flush_delta)
                .map_err(|e| ProxyError::Internal(format!("failed to serialize flush delta: {e}")))?;
            events.push(
                Event::default()
                    .event("content_block_delta")
                    .data(flush_data),
            );
        }
    }

    let translated_data = serde_json::to_string(&translated)
        .map_err(|e| ProxyError::Internal(format!("failed to serialize SSE event: {e}")))?;

    let event_name = match &translated {
        SseEvent::MessageStart { .. } => "message_start",
        SseEvent::ContentBlockStart { .. } => "content_block_start",
        SseEvent::ContentBlockDelta { .. } => "content_block_delta",
        SseEvent::ContentBlockStop { .. } => "content_block_stop",
        SseEvent::MessageDelta { .. } => "message_delta",
        SseEvent::MessageStop { .. } => "message_stop",
        SseEvent::Ping { .. } => "ping",
        SseEvent::Error { .. } => "error",
    };

    events.push(Event::default().event(event_name).data(translated_data));

    Ok(Some(events))
}

/// Fallback handler — logs unmatched requests so we can see what clients are hitting.
async fn fallback(req: axum::extract::Request) -> impl IntoResponse {
    tracing::warn!(
        method = %req.method(),
        uri = %req.uri(),
        "unmatched route"
    );
    (StatusCode::NOT_FOUND, "Not Found")
}

/// Build the Axum router with all routes.
pub fn build_router(state: AppState) -> axum::Router {
    axum::Router::new()
        .route("/v1/messages", axum::routing::post(handle_messages))
        .route("/health", axum::routing::get(health))
        .fallback(fallback)
        .with_state(state)
}
