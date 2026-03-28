use std::ffi::OsString;
use std::path::Path;
use std::sync::Arc;

use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};

use prompt_daemon::config;
use prompt_daemon::state::DaemonState;

/// Watch the config file for changes and reload on modification.
///
/// Watches the parent directory (not the file directly) because editors do
/// atomic saves (write temp → rename), which replaces the inode. An inotify
/// watch on the old inode becomes dead after the first save.
pub fn spawn_config_watcher(
    config_path: &Path,
    state: Arc<DaemonState>,
) -> Result<RecommendedWatcher, Box<dyn std::error::Error>> {
    let config_file = config_path
        .canonicalize()?;
    let config_dir = config_file
        .parent()
        .expect("config file must have a parent directory")
        .to_path_buf();
    let config_filename: OsString = config_file
        .file_name()
        .expect("config file must have a filename")
        .into();

    // Capture the Tokio runtime handle now (while on a Tokio worker thread).
    // The notify callback fires on the inotify thread, which has no Tokio context,
    // so we need the handle to spawn async work from there.
    let handle = tokio::runtime::Handle::current();

    let mut watcher = notify::recommended_watcher(move |res: Result<Event, notify::Error>| {
        match res {
            Ok(event) => {
                // Only react to modifications or creates (atomic saves)
                // that affect our config file.
                let dominated = matches!(
                    event.kind,
                    EventKind::Modify(_) | EventKind::Create(_)
                );
                let affects_config = event
                    .paths
                    .iter()
                    .any(|p| p.file_name() == Some(&config_filename));

                if !dominated || !affects_config {
                    return;
                }

                tracing::info!("config file changed, reloading");

                let state = Arc::clone(&state);
                let path = config_file.clone();

                // Load config synchronously (we're on the inotify thread)
                let new_config = match config::load_config(&path) {
                    Ok(c) => c,
                    Err(e) => {
                        tracing::error!("failed to reload config: {e}");
                        return;
                    }
                };

                handle.spawn(async move {
                    // Diff old vs new config to find changed/removed commands
                    let (changed, removed) = {
                        let old = state.config.read().await;

                        let mut changed = Vec::new();
                        let mut removed = Vec::new();

                        for (name, old_cmd) in &old.commands {
                            match new_config.commands.get(name) {
                                None => removed.push(name.clone()),
                                Some(new_cmd) if new_cmd != old_cmd => {
                                    changed.push(name.clone());
                                }
                                _ => {}
                            }
                        }

                        for name in new_config.commands.keys() {
                            if !old.commands.contains_key(name) {
                                tracing::info!("new command '{name}' added");
                            }
                        }

                        (changed, removed)
                    };

                    // Invalidate cache + cancel schedulers for changed/removed commands
                    if !changed.is_empty() || !removed.is_empty() {
                        let mut store = state.store.write().await;
                        for cmd in &changed {
                            tracing::info!("command '{cmd}' config changed, invalidating cache");
                            store.remove_command(cmd);
                        }
                        for cmd in &removed {
                            tracing::info!("command '{cmd}' removed");
                            store.remove_command(cmd);
                        }
                    }

                    for cmd in changed.iter().chain(removed.iter()) {
                        state.scheduler.cancel_for_command(cmd).await;
                    }

                    // Swap in the new config
                    {
                        let mut config_write = state.config.write().await;
                        *config_write = new_config;
                    }

                    tracing::info!("config reloaded successfully");
                });
            }
            Err(e) => {
                tracing::error!("config watcher error: {e}");
            }
        }
    })?;

    // Watch the directory, not the file — survives atomic saves
    watcher.watch(&config_dir, RecursiveMode::NonRecursive)?;
    tracing::info!("watching config directory: {}", config_dir.display());
    Ok(watcher)
}
