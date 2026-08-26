//! CLI configuration and application state.

use std::path::PathBuf;
use std::sync::Arc;

use clap::Parser;

use crate::creds::CredentialReader;
use crate::usage::UsageState;

/// OAuth shim for Anthropic's API — injects Claude Code credentials and
/// request shape, then forwards to upstream.
#[derive(Parser, Debug)]
#[command(name = "compat-proxy", version, about)]
pub struct AppConfig {
    /// Path to the credentials JSON file.
    #[arg(long, env = "COMPAT_PROXY_CREDENTIALS")]
    pub credentials_path: Option<PathBuf>,

    /// Upstream API base URL.
    #[arg(long, default_value = "https://api.anthropic.com", env = "COMPAT_PROXY_UPSTREAM")]
    pub upstream_url: String,

    /// TCP port to bind to. If not set, uses a Unix socket instead.
    #[arg(long, env = "COMPAT_PROXY_PORT")]
    pub port: Option<u16>,

    /// Unix socket path. Used when --port is not set.
    #[arg(long, env = "COMPAT_PROXY_SOCKET")]
    pub socket: Option<PathBuf>,

    /// Log level filter (e.g., "info", "debug", "compat_proxy=debug,tower=info").
    #[arg(long, default_value = "info", env = "COMPAT_PROXY_LOG")]
    pub log_level: String,

    /// Claude Code version to impersonate. Appears in the user-agent, the
    /// billing fingerprint, and the billing block.
    #[arg(long, default_value = "2.1.97", env = "COMPAT_PROXY_CC_VERSION")]
    pub cc_version: String,

    /// API version header value.
    #[arg(long, default_value = "2023-06-01")]
    pub api_version: String,

    /// Override `max_tokens` on every request. Real CC sends 64000.
    #[arg(long, default_value_t = 64000, env = "COMPAT_PROXY_MAX_TOKENS")]
    pub max_tokens: u64,

    /// Extra beta flags, comma-separated. Merged with the required OAuth betas.
    #[arg(long, env = "COMPAT_PROXY_BETAS")]
    pub betas: Option<String>,
}

impl AppConfig {
    /// Resolve the credentials path, using the default if not specified.
    pub fn credentials_path(&self) -> PathBuf {
        if let Some(ref path) = self.credentials_path {
            return path.clone();
        }
        let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());
        PathBuf::from(home).join(".claude").join(".credentials.json")
    }

    /// Resolve the Unix socket path.
    pub fn socket_path(&self) -> PathBuf {
        if let Some(ref path) = self.socket {
            return path.clone();
        }
        let runtime_dir =
            std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
        PathBuf::from(runtime_dir).join("compat-proxy.sock")
    }
}

/// Required beta flags for OAuth + Claude Code features.
/// From real Claude Code source (constants/oauth.ts, utils/betas.ts).
pub const REQUIRED_OAUTH_BETAS: &[&str] = &[
    "oauth-2025-04-20",
    "claude-code-20250219",
    "interleaved-thinking-2025-05-14",
    "advanced-tool-use-2025-11-20",
    "context-management-2025-06-27",
    "prompt-caching-scope-2026-01-05",
    "effort-2025-11-24",
    "fast-mode-2026-02-01",
];

/// Shared application state, passed to Axum handlers.
#[derive(Clone)]
pub struct AppState {
    /// Credential reader (reads fresh on every request).
    pub creds: Arc<CredentialReader>,

    /// HTTP client for upstream requests.
    pub client: reqwest::Client,

    /// Upstream API base URL.
    pub upstream_url: String,

    /// API version header value.
    pub api_version: String,

    /// Claude Code version being impersonated.
    pub cc_version: String,

    /// Extra beta flags to merge with the required OAuth set.
    pub betas: Option<String>,

    /// `max_tokens` override applied to every request.
    pub max_tokens: u64,

    /// Persistent session ID (generated once at startup, like real CC).
    pub session_id: String,

    /// Persistent device ID (random 64-char hex, generated once at startup).
    pub device_id: String,

    /// Cached rate-limit utilization from upstream response headers.
    pub usage: Arc<UsageState>,
}
