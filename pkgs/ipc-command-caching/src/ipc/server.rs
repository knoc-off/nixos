use std::collections::HashMap;
use std::sync::Arc;

use tokio::net::UnixListener;
use tokio::sync::{Mutex, RwLock, Semaphore};
use tokio::task::JoinHandle;

use crate::cache::resolve;
use crate::cache::store::CacheStore;
use crate::config::schema::{DaemonConfig, ENV_CWD};
use crate::exec::run_command;

use super::protocol;
use super::status::format_status_dump;

/// Shared daemon state passed to each connection handler.
pub struct DaemonState {
    pub config: RwLock<DaemonConfig>,
    pub store: RwLock<CacheStore>,
    pub semaphore: Arc<Semaphore>,
    pub idle_timeout: std::time::Duration,
    /// Active scheduler tasks per cache key.
    pub schedulers: Mutex<HashMap<String, JoinHandle<()>>>,
}

/// Start the IPC server on the given unix socket path.
pub async fn run_server(
    socket_path: &str,
    state: Arc<DaemonState>,
) -> Result<(), Box<dyn std::error::Error>> {
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

/// Derive a deterministic cache key from command name + env vars.
/// Env vars are sorted by name for consistency.
fn derive_cache_key(command: &str, env: &HashMap<String, String>) -> String {
    if env.is_empty() {
        return command.to_string();
    }

    let mut key = command.to_string();
    let mut pairs: Vec<_> = env.iter().collect();
    pairs.sort_by_key(|(k, _)| (*k).clone());
    for (k, v) in pairs {
        key.push('\0');
        key.push_str(k);
        key.push('=');
        key.push_str(v);
    }
    key
}

async fn handle_connection(
    stream: tokio::net::UnixStream,
    state: Arc<DaemonState>,
) -> Result<(), Box<dyn std::error::Error>> {
    let (mut reader, mut writer) = stream.into_split();

    // ── Phase 1: read command name + CWD ────────────────────────────
    let (command, cwd, is_status) = protocol::read_command(&mut reader).await?;

    if is_status {
        let store = state.store.read().await;
        let config = state.config.read().await;
        let dump = format_status_dump(&store, &config);
        protocol::write_response(&mut writer, 0x01, &dump).await?;
        return Ok(());
    }

    let config = state.config.read().await;

    // Look up command config
    let cmd_config = match config.commands.get(&command) {
        Some(cmd) => cmd,
        None => {
            tracing::debug!("unknown command: '{command}'");
            // Full 4-phase: send empty env request, read empty values, respond EMPTY
            protocol::write_env_request(&mut writer, &[]).await?;
            let _ = protocol::read_env_values(&mut reader).await?;
            protocol::write_response(&mut writer, 0x04, "").await?;
            return Ok(());
        }
    };

    // ── Phase 2: send required env var names (excluding CWD) ────────
    let client_vars = cmd_config.client_env_vars();
    protocol::write_env_request(&mut writer, &client_vars).await?;

    // ── Phase 3: read env var values from client ────────────────────
    let client_values = protocol::read_env_values(&mut reader).await?;

    // Build the full env HashMap: CWD (from phase 1) + client vars (from phase 3)
    let mut env: HashMap<String, String> = client_vars
        .into_iter()
        .zip(client_values.into_iter())
        .collect();

    // Insert CWD if this command uses it
    if cmd_config.uses_cwd() {
        env.insert(ENV_CWD.to_string(), cwd.clone());
    }

    // ── Phase 4: resolve and respond ────────────────────────────────

    // Derive cache key from command name + all env vars that participate
    let cache_key = derive_cache_key(&command, &env);

    let mut store = state.store.write().await;
    let entry = store.get_or_create(&cache_key);
    entry.activity.touch();
    entry.last_env = env.clone();

    let (status, value, should_exec) =
        resolve::resolve(&entry.cache, cmd_config, &config.defaults, &env);

    if should_exec && !entry.cache.is_running() {
        entry.cache.start();

        let run = cmd_config.run.clone();
        let shell = cmd_config.effective_shell(&config.defaults);
        let timeout = cmd_config.effective_timeout(&config.defaults);
        let exec_cwd = if cmd_config.exec_in_cwd {
            Some(cwd.clone())
        } else {
            None
        };
        let env_clone = env.clone();
        let key = cache_key.clone();
        let state2 = Arc::clone(&state);

        let cmd_name = command.clone();
        let cmd_config_clone = cmd_config.clone();
        let defaults_clone = config.defaults.clone();
        let idle_timeout = state.idle_timeout;

        drop(store);
        drop(config);

        // Spawn one-shot execution
        tokio::spawn(async move {
            tracing::debug!("executing command for key '{key}'");

            let result = run_command(
                &run,
                shell,
                &env_clone,
                timeout,
                exec_cwd.as_deref(),
            )
            .await;

            let mut store = state2.store.write().await;
            if let Some(entry) = store.get_mut(&key) {
                match result {
                    Ok(output) => {
                        tracing::debug!("command for '{key}' completed: {output}");
                        entry.cache.complete(output, env_clone);
                    }
                    Err(e) => {
                        tracing::warn!("command for '{key}' failed: {e}");
                        entry.cache.fail(e);
                    }
                }
            }
        });

        // Start interval poller if needed
        ensure_scheduler(
            &state,
            cache_key,
            cmd_name,
            cmd_config_clone,
            defaults_clone,
            idle_timeout,
        )
        .await;

        protocol::write_response(&mut writer, status, &value).await?;
    } else {
        protocol::write_response(&mut writer, status, &value).await?;
    }

    Ok(())
}

/// Start a scheduler polling task for a cache key if one isn't already running.
async fn ensure_scheduler(
    state: &Arc<DaemonState>,
    cache_key: String,
    _cmd_name: String,
    cmd_config: crate::config::schema::CommandConfig,
    defaults: crate::config::schema::DefaultsSection,
    idle_timeout: std::time::Duration,
) {
    let interval_duration = cmd_config
        .interval
        .as_ref()
        .map(|d| d.0)
        .unwrap_or(std::time::Duration::from_secs(0));

    if interval_duration.is_zero() {
        return;
    }

    let mut schedulers = state.schedulers.lock().await;

    if let Some(handle) = schedulers.get(&cache_key) {
        if !handle.is_finished() {
            return;
        }
    }

    tracing::info!("starting scheduler for key '{cache_key}' (interval: {interval_duration:?})");

    let state2 = Arc::clone(state);
    let key = cache_key.clone();
    let exec_in_cwd = cmd_config.exec_in_cwd;

    let handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(interval_duration);
        interval.tick().await; // skip first immediate tick

        loop {
            interval.tick().await;

            // Check if key is cold
            {
                let store = state2.store.read().await;
                match store.get(&key) {
                    Some(entry) if entry.activity.is_hot(idle_timeout) => {}
                    _ => {
                        tracing::debug!("key '{key}' is cold, stopping scheduler");
                        return;
                    }
                }
            }

            // Check expiry
            if let Some(ref max_age) = cmd_config.max_age {
                let mut store = state2.store.write().await;
                if let Some(entry) = store.get_mut(&key) {
                    entry.cache.check_expiry(max_age.0);
                }
            }

            // Skip if already running
            {
                let store = state2.store.read().await;
                if let Some(entry) = store.get(&key) {
                    if entry.cache.is_running() {
                        continue;
                    }
                }
            }

            // Try to acquire a worker permit (non-blocking)
            let permit = match state2.semaphore.clone().try_acquire_owned() {
                Ok(p) => p,
                Err(_) => {
                    tracing::trace!("no worker permits, skipping tick for '{key}'");
                    continue;
                }
            };

            // Transition to Running and grab the env snapshot
            let env_snapshot;
            {
                let mut store = state2.store.write().await;
                if let Some(entry) = store.get_mut(&key) {
                    if !entry.cache.start() {
                        continue;
                    }
                    env_snapshot = entry.last_env.clone();
                } else {
                    continue;
                }
            }

            let run = cmd_config.run.clone();
            let shell = cmd_config.effective_shell(&defaults);
            let timeout = cmd_config.effective_timeout(&defaults);
            let exec_cwd = if exec_in_cwd {
                env_snapshot.get(ENV_CWD).cloned()
            } else {
                None
            };
            let state3 = Arc::clone(&state2);
            let key2 = key.clone();

            tokio::spawn(async move {
                let _permit = permit;

                let result = run_command(
                    &run,
                    shell,
                    &env_snapshot,
                    timeout,
                    exec_cwd.as_deref(),
                )
                .await;

                let mut store = state3.store.write().await;
                if let Some(entry) = store.get_mut(&key2) {
                    match result {
                        Ok(output) => {
                            tracing::debug!("scheduler: '{key2}' completed: {output}");
                            entry.cache.complete(output, env_snapshot);
                        }
                        Err(e) => {
                            tracing::warn!("scheduler: '{key2}' failed: {e}");
                            entry.cache.fail(e);
                        }
                    }
                }
            });
        }
    });

    schedulers.insert(cache_key, handle);
}
