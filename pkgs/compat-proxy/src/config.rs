//! CLI configuration and application state.

use std::path::PathBuf;
use std::sync::Arc;

use arc_swap::ArcSwap;
use clap::Parser;

use crate::creds::CredentialReader;
use crate::rules::RuleSet;
use crate::session_log::SessionLogger;

/// Compatibility proxy — translates client API requests into
/// upstream-compatible format using TOML rule files.
#[derive(Parser, Debug)]
#[command(name = "compat-proxy", version, about)]
pub struct AppConfig {
    /// Directory containing rule files (*.toml) and the schema registry.
    #[arg(long, default_value = "rules")]
    pub rules_dir: PathBuf,

    /// Path to the schema registry file.
    #[arg(long, default_value = "rules/cc-schemas.toml")]
    pub schema_registry: PathBuf,

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

    /// Dump request/response bodies to files for debugging.
    /// WARNING: This logs sensitive data. Off by default.
    #[arg(long, default_value_t = false)]
    pub dump_requests: bool,

    /// Enable per-session JSONL transaction logging.
    /// Writes one line per request to
    /// `$XDG_STATE_HOME/compat-proxy/sessions/<session_id>.jsonl`
    /// (or override with --session-log-dir).
    /// Replaces the old per-file `/tmp/proxy-*.json` dump format.
    #[arg(long, default_value_t = false)]
    pub session_log: bool,

    /// Override directory for session log files.
    /// Defaults to `$XDG_STATE_HOME/compat-proxy/sessions`.
    #[arg(long)]
    pub session_log_dir: Option<PathBuf>,

    /// API version header value.
    #[arg(long, default_value = "2023-06-01")]
    pub api_version: String,

    /// Beta feature flags to include in the upstream request (comma-separated).
    #[arg(long, env = "COMPAT_PROXY_BETAS")]
    pub betas: Option<String>,
}

impl AppConfig {
    /// Resolve the credentials path, using the default if not specified.
    pub fn credentials_path(&self) -> PathBuf {
        if let Some(ref path) = self.credentials_path {
            path.clone()
        } else {
            // Default: ~/.claude/.credentials.json
            let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());
            PathBuf::from(home)
                .join(".claude")
                .join(".credentials.json")
        }
    }

    /// Resolve the Unix socket path.
    pub fn socket_path(&self) -> PathBuf {
        if let Some(ref path) = self.socket {
            path.clone()
        } else {
            let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
                .unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(runtime_dir).join("compat-proxy.sock")
        }
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

/// Billing fingerprint constants (from real CC utils/fingerprint.ts).
pub const BILLING_HASH_SALT: &str = "59cf53e54c78";
pub const BILLING_HASH_INDICES: &[usize] = &[4, 7, 20];

/// Shared application state, passed to Axum handlers.
#[derive(Clone)]
pub struct AppState {
    /// Hot-reloadable rule set. SIGHUP swaps this atomically.
    pub rules: Arc<ArcSwap<RuleSet>>,

    /// Credential reader (reads fresh on every request).
    pub creds: Arc<CredentialReader>,

    /// HTTP client for upstream requests.
    pub client: reqwest::Client,

    /// Upstream API base URL.
    pub upstream_url: String,

    /// API version header value.
    pub api_version: String,

    /// Beta flags to inject.
    pub betas: Option<String>,

    /// Whether to dump request/response bodies.
    pub dump_requests: bool,

    /// Optional session-log writer (None when --session-log is not set).
    pub session_log: Option<Arc<SessionLogger>>,

    /// Persistent session ID (generated once at startup, like real CC).
    pub session_id: String,

    /// Persistent device ID (random 64-char hex, generated once at startup).
    pub device_id: String,
}
