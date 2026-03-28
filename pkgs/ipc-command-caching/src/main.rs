mod reload;

use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::{Mutex, RwLock, Semaphore};

use prompt_daemon::cache::store::CacheStore;
use prompt_daemon::config;
use prompt_daemon::ipc::server::{run_server, DaemonState};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Parse --config flag
    let config_path_arg = std::env::args()
        .skip_while(|a| a != "--config")
        .nth(1);

    let config_path = config::resolve_config_path(config_path_arg.as_deref())
        .ok_or("no config file found (use --config or place at ~/.config/prompt-daemon/config.yaml)")?;

    let daemon_config = config::load_config(&config_path)?;

    // Set up logging
    let log_level = daemon_config.daemon.log_level.clone();
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(&log_level)),
        )
        .init();

    tracing::info!("starting prompt-daemon v{}", env!("CARGO_PKG_VERSION"));
    tracing::info!("config loaded from {}", config_path.display());

    let socket_path = config::socket_path();
    let workers = daemon_config.daemon.workers;
    let idle_timeout = daemon_config.daemon.idle_timeout.0;

    // Shared state
    let state = Arc::new(DaemonState {
        config: RwLock::new(daemon_config),
        store: RwLock::new(CacheStore::new()),
        semaphore: Arc::new(Semaphore::new(workers)),
        idle_timeout,
        schedulers: Mutex::new(HashMap::new()),
    });

    // Start config file watcher
    let _watcher = reload::spawn_config_watcher(&config_path, Arc::clone(&state))?;

    tracing::info!(
        "socket: {}, workers: {workers}, idle_timeout: {idle_timeout:?}",
        socket_path.display()
    );

    // Run the IPC server (blocks forever)
    run_server(socket_path.to_str().unwrap(), state).await?;

    Ok(())
}
