use std::path::Path;
use std::sync::Arc;

use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use prompt_daemon::config;
use prompt_daemon::ipc::server::DaemonState;

/// Watch the config file for changes and reload on modification.
pub fn spawn_config_watcher(
    config_path: &Path,
    state: Arc<DaemonState>,
) -> Result<RecommendedWatcher, Box<dyn std::error::Error>> {
    let path = config_path.to_path_buf();

    let mut watcher = notify::recommended_watcher(move |res: Result<Event, notify::Error>| {
        match res {
            Ok(event) => {
                if matches!(event.kind, EventKind::Modify(_)) {
                    tracing::info!("config file changed, reloading");

                    let state = Arc::clone(&state);
                    let path = path.clone();

                    // Load config synchronously before spawning async task
                    let new_config = match config::load_config(&path) {
                        Ok(c) => c,
                        Err(e) => {
                            tracing::error!("failed to reload config: {e}");
                            return;
                        }
                    };

                    tokio::spawn(async move {
                        let new_commands: Vec<String> =
                            new_config.commands.keys().cloned().collect();

                        let old_commands: Vec<String> = {
                            let old = state.config.read().await;
                            old.commands.keys().cloned().collect()
                        };

                        {
                            let mut store_write = state.store.write().await;
                            for cmd in &old_commands {
                                if !new_commands.contains(cmd) {
                                    tracing::info!("command '{cmd}' removed from config");
                                }
                            }
                            store_write.retain_commands(&new_commands);
                        }

                        {
                            let mut config_write = state.config.write().await;
                            *config_write = new_config;
                        }

                        tracing::info!("config reloaded successfully");
                    });
                }
            }
            Err(e) => {
                tracing::error!("config watcher error: {e}");
            }
        }
    })?;

    watcher.watch(config_path, RecursiveMode::NonRecursive)?;
    Ok(watcher)
}
