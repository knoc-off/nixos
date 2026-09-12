use std::collections::HashMap;
use std::sync::Arc;

use tokio::net::UnixListener;

use crate::cache::key::derive_cache_key;
use crate::cache::resolve;
use crate::config::schema::ENV_CWD;
use crate::state::DaemonState;

use super::protocol;
use super::status::format_status_dump;

type Error = Box<dyn std::error::Error + Send + Sync>;

/// Start the IPC server on the given unix socket path.
pub async fn run_server(socket_path: &str, state: Arc<DaemonState>) -> Result<(), Error> {
    let _ = std::fs::remove_file(socket_path);

    let listener = UnixListener::bind(socket_path)?;
    tracing::info!("listening on {socket_path}");

    loop {
        match listener.accept().await {
            Ok((stream, _addr)) => {
                let state = Arc::clone(&state);
                tokio::spawn(async move {
                    if let Err(e) = handle_connection(stream, state).await {
                        tracing::debug!("connection error: {e}");
                    }
                });
            }
            Err(e) => {
                tracing::error!("accept error: {e}");
            }
        }
    }
}

async fn handle_connection(
    stream: tokio::net::UnixStream,
    state: Arc<DaemonState>,
) -> Result<(), Error> {
    let (mut reader, mut writer) = stream.into_split();

    let request = match protocol::read_request(&mut reader).await? {
        Some(req) => req,
        None => {
            tracing::debug!("status query");
            let store = state.store.read().await;
            let dump = format_status_dump(&store);
            protocol::write_response(&mut writer, 0x01, &dump).await?;
            return Ok(());
        }
    };
    let (command, cwd, client_env) = (request.command, request.cwd, request.env);

    tracing::debug!(cmd = %command, cwd = %cwd, "request");

    // Look up command in config
    let cmd_config = match state.config.commands.get(&command) {
        Some(cmd) => cmd,
        None => {
            tracing::debug!(cmd = %command, "unknown command");
            protocol::write_response(&mut writer, 0x04, "").await?;
            return Ok(());
        }
    };

    // Filter the client's full environment down to what this command declared.
    let mut env: HashMap<String, String> = cmd_config
        .client_env_vars()
        .into_iter()
        .filter_map(|name| client_env.get(&name).map(|v| (name, v.clone())))
        .collect();

    if cmd_config.uses_cwd() {
        env.insert(ENV_CWD.to_string(), cwd);
    }

    // Clone config data we need (state.config is immutable for the daemon's lifetime)
    let cmd_config = cmd_config.clone();
    let defaults = state.config.defaults.clone();

    // Derive cache key and resolve response
    let cache_key = derive_cache_key(&command, &env);

    let (status, value, should_exec) = {
        let mut store = state.store.write().await;
        let entry = store.get_or_create(&cache_key);
        entry.activity.touch();
        entry.last_env = env.clone();

        let result = resolve::resolve(&entry.cache, &cmd_config, &defaults, &env);

        // Transition to Running if execution is needed
        if result.2 && !entry.cache.is_running() {
            entry.cache.start();
        }

        result
    };
    // store lock dropped here

    tracing::debug!(
        cmd = %command,
        status = format!("0x{:02x}", status),
        should_exec,
        "resolved"
    );

    // One-shot execution on cache miss (fire-and-forget)
    if should_exec {
        let shell = cmd_config.effective_shell(&defaults);
        let timeout = cmd_config.effective_timeout(&defaults);
        state.scheduler.execute_now(
            &state,
            &cache_key,
            &cmd_config.run,
            shell,
            timeout,
            env,
            cmd_config.exec_in_cwd,
        );
    }

    // Ensure scheduler is alive — called unconditionally to fix lifecycle bug
    // (previously only called on cache miss, leaving schedulers dead after cold timeout)
    state
        .scheduler
        .ensure_active(&state, &cache_key, &cmd_config, &defaults)
        .await;

    // Send response
    protocol::write_response(&mut writer, status, &value).await?;

    Ok(())
}
