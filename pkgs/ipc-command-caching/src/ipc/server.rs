use std::collections::HashMap;
use std::sync::Arc;

use tokio::net::UnixListener;

use crate::cache::key::derive_cache_key;
use crate::cache::resolve;
use crate::config::schema::ENV_CWD;
use crate::error::Error;
use crate::state::DaemonState;

use super::protocol;
use super::status::format_status_dump;

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

    // Phase 1: read command name + CWD
    let (command, cwd, is_status) = protocol::read_command(&mut reader).await?;

    // Status query shortcut (skip phases 2-3)
    if is_status {
        tracing::debug!("status query");
        let store = state.store.read().await;
        let dump = format_status_dump(&store);
        protocol::write_response(&mut writer, 0x01, &dump).await?;
        return Ok(());
    }

    tracing::debug!(cmd = %command, cwd = %cwd, "request");

    // Look up command in config
    let config = state.config.read().await;
    let cmd_config = match config.commands.get(&command) {
        Some(cmd) => cmd,
        None => {
            tracing::debug!(cmd = %command, "unknown command");
            protocol::write_env_request(&mut writer, &[]).await?;
            let _ = protocol::read_env_values(&mut reader).await?;
            protocol::write_response(&mut writer, 0x04, "").await?;
            return Ok(());
        }
    };

    // Phase 2: send required env var names
    let client_vars = cmd_config.client_env_vars();
    protocol::write_env_request(&mut writer, &client_vars).await?;

    // Phase 3: receive env var values
    let client_values = protocol::read_env_values(&mut reader).await?;
    let mut env: HashMap<String, String> =
        client_vars.into_iter().zip(client_values).collect();

    if cmd_config.uses_cwd() {
        env.insert(ENV_CWD.to_string(), cwd);
    }

    // Clone config data we need, then release the read lock
    let cmd_config = cmd_config.clone();
    let defaults = config.defaults.clone();
    drop(config);

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

    // Phase 4: send response
    protocol::write_response(&mut writer, status, &value).await?;

    Ok(())
}
