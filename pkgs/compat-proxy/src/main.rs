//! compat-proxy — typed API compatibility proxy.
//!
//! Translates incoming requests from arbitrary client formats into
//! upstream-compatible format using TOML rule files, then forwards
//! to the upstream API with credentials from a local file.

use std::path::Path;
use std::sync::Arc;

use arc_swap::ArcSwap;
use clap::Parser;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

use compat_proxy::config::{AppConfig, AppState};
use compat_proxy::creds::CredentialReader;
use compat_proxy::proxy;
use compat_proxy::rules::{validate_rules, RuleSet, SchemaRegistry};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let config = AppConfig::parse();

    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new(&config.log_level)),
        )
        .init();

    tracing::info!("compat-proxy starting");

    // Load schema registry
    let registry = SchemaRegistry::load(&config.schema_registry).map_err(|e| {
        tracing::error!("failed to load schema registry: {e}");
        e
    })?;
    tracing::info!(
        "loaded schema registry from {} ({} tools)",
        config.schema_registry.display(),
        registry.tool_names().count()
    );

    // Load and validate rule files
    let rule_set = load_rules(&config.rules_dir, &registry)?;
    tracing::info!(
        "loaded rules for client '{}' (cc_version: {}, {} tool renames, {} tool drops)",
        rule_set.client_name,
        rule_set.cc_version,
        rule_set.tool_renames.len(),
        rule_set.tool_drops.len()
    );

    // Set up credentials reader
    let creds_path = config.credentials_path();
    let creds = CredentialReader::new(creds_path.clone());

    // Verify credentials are readable at startup (warn, don't fail)
    match creds.read_token() {
        Ok(_) => tracing::info!("credentials readable at {}", creds_path.display()),
        Err(e) => tracing::warn!(
            "credentials not readable at startup: {e}. \
             Requests will fail until credentials are available."
        ),
    }

    // Build HTTP client (no default user-agent — stainless headers handle this)
    let client = reqwest::Client::builder()
        .no_proxy()
        .build()?;

    // Generate persistent per-instance identifiers (like real CC)
    let session_id = uuid::Uuid::new_v4().to_string();
    let device_id = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let bytes: Vec<u8> = (0..32).map(|_| rng.gen()).collect();
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    };

    tracing::info!("session_id: {session_id}");
    tracing::debug!("device_id: {device_id}");

    // Build application state
    let state = AppState {
        rules: Arc::new(ArcSwap::new(Arc::new(rule_set))),
        creds: Arc::new(creds),
        client,
        upstream_url: config.upstream_url.clone(),
        api_version: config.api_version.clone(),
        betas: config.betas.clone(),
        dump_requests: config.dump_requests,
        session_id,
        device_id,
    };

    // Set up SIGHUP handler for hot reload
    let reload_state = state.clone();
    let reload_rules_dir = config.rules_dir.clone();
    let reload_registry = registry;
    tokio::spawn(async move {
        let mut signal =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup())
                .expect("failed to register SIGHUP handler");

        loop {
            signal.recv().await;
            tracing::info!("SIGHUP received, reloading rules...");

            match load_rules(&reload_rules_dir, &reload_registry) {
                Ok(new_rules) => {
                    tracing::info!(
                        "rules reloaded successfully for client '{}'",
                        new_rules.client_name
                    );
                    reload_state.rules.store(Arc::new(new_rules));
                }
                Err(e) => {
                    tracing::error!(
                        "failed to reload rules, keeping old rules: {e}"
                    );
                }
            }
        }
    });

    // Build router
    let app = proxy::build_router(state);

    // Bind and serve
    if let Some(port) = config.port {
        // TCP mode
        let addr = format!("127.0.0.1:{port}");
        let listener = TcpListener::bind(&addr).await?;
        tracing::info!("listening on {addr}");
        axum::serve(listener, app).await?;
    } else {
        // Unix socket mode
        let socket_path = config.socket_path();

        // Remove existing socket file if it exists
        if socket_path.exists() {
            std::fs::remove_file(&socket_path)?;
        }

        // Ensure parent directory exists
        if let Some(parent) = socket_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let listener = tokio::net::UnixListener::bind(&socket_path)?;
        tracing::info!("listening on unix:{}", socket_path.display());
        axum::serve(listener, app).await?;
    }

    Ok(())
}

/// Load all rule files from the rules directory and merge them.
///
/// Currently supports a single client rule file. The file is found by
/// looking for TOML files in the rules directory that aren't the schema
/// registry (cc-schemas.toml).
fn load_rules(
    rules_dir: &Path,
    registry: &SchemaRegistry,
) -> Result<RuleSet, Box<dyn std::error::Error + Send + Sync>> {
    let entries = std::fs::read_dir(rules_dir).map_err(|e| {
        format!(
            "failed to read rules directory '{}': {e}",
            rules_dir.display()
        )
    })?;

    let mut rule_file_path = None;

    for entry in entries {
        let entry = entry?;
        let path = entry.path();

        if path.extension().map_or(false, |ext| ext == "toml") {
            let name = path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy();

            // Skip the schema registry file
            if name == "cc-schemas.toml" {
                continue;
            }

            if rule_file_path.is_some() {
                tracing::warn!(
                    "multiple rule files found; using first one. Ignoring: {}",
                    path.display()
                );
                continue;
            }

            rule_file_path = Some(path);
        }
    }

    let rule_file_path = rule_file_path.ok_or_else(|| {
        format!(
            "no rule files found in '{}'. Expected a .toml file.",
            rules_dir.display()
        )
    })?;

    tracing::info!("loading rules from {}", rule_file_path.display());

    let content = std::fs::read_to_string(&rule_file_path)?;
    let rules_file: compat_proxy::rules::RulesFile =
        toml::from_str(&content).map_err(|e| {
            format!(
                "failed to parse rule file '{}': {e}",
                rule_file_path.display()
            )
        })?;

    let rule_set =
        validate_rules(&rules_file, registry, rules_dir).map_err(|errors| {
            let error_list = errors
                .iter()
                .map(|e| format!("  - {e}"))
                .collect::<Vec<_>>()
                .join("\n");
            format!(
                "rule validation failed for '{}':\n{error_list}",
                rule_file_path.display()
            )
        })?;

    Ok(rule_set)
}
