//! compat-proxy — OAuth shim for Anthropic's API.
//!
//! Anthropic only serves OAuth (Claude Pro/Max) credentials to requests
//! that look like they came from Claude Code. This forwards `/v1/messages`
//! to upstream with Claude Code's credentials, headers and request shape
//! attached, so any Anthropic-compatible client can use them.
//!
//! It deliberately knows nothing about prompts or tools — that is the
//! client's business.

use std::sync::Arc;

use clap::Parser;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

use compat_proxy::config::{AppConfig, AppState};
use compat_proxy::creds::CredentialReader;
use compat_proxy::proxy;
use compat_proxy::usage::UsageState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let config = AppConfig::parse();

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new(&config.log_level)),
        )
        .init();

    tracing::info!(
        cc_version = %config.cc_version,
        max_tokens = config.max_tokens,
        "compat-proxy starting"
    );

    let creds_path = config.credentials_path();
    let creds = CredentialReader::new(creds_path.clone());

    // Warn rather than fail: credentials can appear after startup, and a
    // proxy that refuses to boot without them is harder to debug than one
    // that returns a clear 503 per request.
    match creds.read_token() {
        Ok(_) => tracing::info!("credentials readable at {}", creds_path.display()),
        Err(e) => tracing::warn!(
            "credentials not readable at startup: {e}. \
             Requests will fail until credentials are available."
        ),
    }

    // No default user-agent — the Stainless headers supply it.
    let client = reqwest::Client::builder().no_proxy().build()?;

    // Persistent per-instance identifiers, like real CC.
    let session_id = uuid::Uuid::new_v4().to_string();
    let device_id = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..32).map(|_| format!("{:02x}", rng.gen::<u8>())).collect()
    };
    tracing::info!("session_id: {session_id}");
    tracing::debug!("device_id: {device_id}");

    let state = AppState {
        creds: Arc::new(creds),
        client,
        upstream_url: config.upstream_url.clone(),
        api_version: config.api_version.clone(),
        cc_version: config.cc_version.clone(),
        betas: config.betas.clone(),
        max_tokens: config.max_tokens,
        session_id,
        device_id,
        usage: Arc::new(UsageState::default()),
    };

    let app = proxy::build_router(state);

    if let Some(port) = config.port {
        let addr = format!("127.0.0.1:{port}");
        let listener = TcpListener::bind(&addr).await?;
        tracing::info!("listening on {addr}");
        axum::serve(listener, app).await?;
    } else {
        let socket_path = config.socket_path();

        // A leftover socket from a crashed run would make bind() fail with
        // EADDRINUSE even though nothing is listening.
        if socket_path.exists() {
            std::fs::remove_file(&socket_path)?;
        }
        if let Some(parent) = socket_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let listener = tokio::net::UnixListener::bind(&socket_path)?;
        tracing::info!("listening on unix:{}", socket_path.display());
        axum::serve(listener, app).await?;
    }

    Ok(())
}
