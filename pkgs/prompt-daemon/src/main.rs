mod reload;

use std::sync::Arc;

use prompt_daemon::config;
use prompt_daemon::ipc::server::run_server;
use prompt_daemon::state::DaemonState;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Parse --config flag
    let config_path_arg = std::env::args().skip_while(|a| a != "--config").nth(1);

    let config_path = config::resolve_config_path(config_path_arg.as_deref()).ok_or(
        "no config file found (use --config or place at ~/.config/prompt-daemon/config.yaml)",
    )?;

    let daemon_config = config::load_config(&config_path)?;

    // Set up logging to stdout
    let log_level = daemon_config.daemon.log_level.clone();
    tracing_subscriber::fmt()
        .with_writer(std::io::stdout)
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

    tracing::info!(
        commands = daemon_config.commands.len(),
        workers,
        ?idle_timeout,
        socket = %socket_path.display(),
        "daemon configured"
    );

    for (name, cmd) in &daemon_config.commands {
        tracing::info!(
            name,
            run = %cmd.run,
            has_check = cmd.check.is_some(),
            has_watch = !cmd.watch.is_empty(),
            has_interval = cmd.interval.is_some(),
            "registered command"
        );
    }

    let state = Arc::new(DaemonState::new(daemon_config, workers, idle_timeout));

    // Start config file watcher
    let _watcher = reload::spawn_config_watcher(&config_path, Arc::clone(&state))?;

    // Run the IPC server (blocks forever)
    run_server(socket_path.to_str().unwrap(), state).await?;

    Ok(())
}
