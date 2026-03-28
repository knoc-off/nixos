use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use tokio::sync::{Mutex, Semaphore};
use tokio::task::JoinHandle;
use tokio::time::{interval, sleep, Interval, MissedTickBehavior};

use crate::config::schema::{CommandConfig, DefaultsSection, ENV_CWD};
use crate::exec::run_command;
use crate::state::DaemonState;

/// Manages background scheduler tasks for cache key refresh.
pub struct Scheduler {
    semaphore: Arc<Semaphore>,
    idle_timeout: Duration,
    tasks: Mutex<HashMap<String, JoinHandle<()>>>,
}

impl Scheduler {
    pub fn new(workers: usize, idle_timeout: Duration) -> Self {
        Self {
            semaphore: Arc::new(Semaphore::new(workers)),
            idle_timeout,
            tasks: Mutex::new(HashMap::new()),
        }
    }

    /// Ensure a scheduler task is running for the given cache key.
    /// Called on every request — restarts dead/cold schedulers.
    pub async fn ensure_active(
        &self,
        state: &Arc<DaemonState>,
        cache_key: &str,
        cmd_config: &CommandConfig,
        defaults: &DefaultsSection,
    ) {
        if !cmd_config.has_scheduler() {
            return;
        }

        let mut tasks = self.tasks.lock().await;
        if let Some(handle) = tasks.get(cache_key) {
            if !handle.is_finished() {
                return;
            }
        }

        let idle_timeout = cmd_config.effective_idle_timeout(self.idle_timeout);
        tracing::info!(
            "starting scheduler for key '{cache_key}' (idle_timeout: {idle_timeout:?})"
        );

        let state = Arc::clone(state);
        let key = cache_key.to_string();
        let cmd_config = cmd_config.clone();
        let defaults = defaults.clone();

        let handle = tokio::spawn(async move {
            scheduler_loop(state, key, cmd_config, defaults, idle_timeout).await;
        });

        tasks.insert(cache_key.to_string(), handle);
    }

    /// Cancel all scheduler tasks for a given command name.
    /// Used on config reload when a command's config has changed.
    pub async fn cancel_for_command(&self, command: &str) {
        let mut tasks = self.tasks.lock().await;
        tasks.retain(|key, handle| {
            let cmd_name = key.split('\0').next().unwrap_or(key);
            if cmd_name == command {
                tracing::info!("cancelling scheduler for changed command '{command}' (key '{key}')");
                handle.abort();
                false
            } else {
                true
            }
        });
    }

    /// Execute a command immediately (one-shot, for cache misses).
    /// The caller must have already transitioned the cache entry to Running.
    pub fn execute_now(
        &self,
        state: &Arc<DaemonState>,
        key: &str,
        run: &str,
        shell: bool,
        timeout: Duration,
        env: HashMap<String, String>,
        exec_in_cwd: bool,
    ) {
        let exec_cwd = if exec_in_cwd {
            env.get(ENV_CWD).cloned()
        } else {
            None
        };

        let run = run.to_string();
        let key = key.to_string();
        let state = Arc::clone(state);

        tokio::spawn(async move {
            tracing::debug!("executing command for key '{key}'");
            let result = run_command(&run, shell, &env, timeout, exec_cwd.as_deref()).await;

            let mut store = state.store.write().await;
            if let Some(entry) = store.get_mut(&key) {
                match result {
                    Ok(output) => {
                        tracing::debug!("command for '{key}' completed: {output}");
                        entry.cache.complete(output, env);
                    }
                    Err(e) => {
                        tracing::warn!("command for '{key}' failed: {e}");
                        entry.cache.fail(e);
                    }
                }
            }
        });
    }
}

// ── Scheduler loop (background task per cache key) ─────────────────

async fn scheduler_loop(
    state: Arc<DaemonState>,
    key: String,
    cmd_config: CommandConfig,
    defaults: DefaultsSection,
    idle_timeout: Duration,
) {
    let exec_in_cwd = cmd_config.exec_in_cwd;
    let shell = cmd_config.effective_shell(&defaults);
    let timeout = cmd_config.effective_timeout(&defaults);

    let has_interval = cmd_config.interval.is_some();
    let mut interval_timer = make_timer(cmd_config.interval.as_ref().map(|d| d.0));

    let check_cmd = cmd_config.check.clone();
    let has_check = check_cmd.is_some();
    let mut check_timer = make_timer(cmd_config.effective_check_interval());

    let (watch_tx, mut watch_rx) = tokio::sync::mpsc::channel::<()>(16);
    let _watcher = setup_file_watcher(&cmd_config.watch, &state, &key, watch_tx).await;
    let has_watch = !cmd_config.watch.is_empty();

    let debounce_dur = Duration::from_millis(100);

    loop {
        // Stop if the key has gone cold
        {
            let store = state.store.read().await;
            match store.get(&key) {
                Some(entry) if entry.activity.is_hot(idle_timeout) => {}
                _ => {
                    tracing::debug!("key '{key}' is cold, stopping scheduler");
                    return;
                }
            }
        }

        // Check max_age expiry
        if let Some(ref max_age) = cmd_config.max_age {
            let mut store = state.store.write().await;
            if let Some(entry) = store.get_mut(&key) {
                entry.cache.check_expiry(max_age.0);
            }
        }

        enum Trigger {
            Interval,
            Check,
            Watch,
        }

        let trigger = tokio::select! {
            _ = interval_timer.tick(), if has_interval => Trigger::Interval,
            _ = check_timer.tick(), if has_check => Trigger::Check,
            msg = watch_rx.recv(), if has_watch => {
                if msg.is_none() {
                    tracing::debug!("file watcher closed for '{key}'");
                    continue;
                }
                Trigger::Watch
            },
        };

        match trigger {
            Trigger::Interval => {
                tracing::trace!("interval tick for '{key}'");
                execute_run(&state, &key, &cmd_config.run, shell, timeout, exec_in_cwd).await;
            }
            Trigger::Check => {
                if let Some(ref check) = check_cmd {
                    if run_check(&state, &key, check, shell, timeout, exec_in_cwd).await {
                        tracing::debug!("check changed for '{key}', re-executing");
                        execute_run(&state, &key, &cmd_config.run, shell, timeout, exec_in_cwd)
                            .await;
                    }
                }
            }
            Trigger::Watch => {
                sleep(debounce_dur).await;
                while watch_rx.try_recv().is_ok() {}
                tracing::debug!("file change detected for '{key}', re-executing");
                // Run inline (blocking this loop) so the command finishes before
                // we return to select!. This prevents a feedback loop where the
                // command reads the watched file and triggers another event.
                execute_inline(&state, &key, &cmd_config.run, shell, timeout, exec_in_cwd)
                    .await;
                // Post-execution drain: catch events caused by the execution itself
                sleep(debounce_dur).await;
                while watch_rx.try_recv().is_ok() {}
            }
        }
    }
}

// ── Scheduler helper functions ─────────────────────────────────────

/// Create a tokio interval timer, or a far-future dummy that never fires.
fn make_timer(dur: Option<Duration>) -> Interval {
    let d = dur.unwrap_or(Duration::from_secs(86400 * 365));
    let mut t = interval(d);
    t.set_missed_tick_behavior(MissedTickBehavior::Skip);
    t
}

/// Run the main command via the scheduler and update the cache.
async fn execute_run(
    state: &Arc<DaemonState>,
    key: &str,
    run: &str,
    shell: bool,
    timeout: Duration,
    exec_in_cwd: bool,
) {
    // Skip if already running
    {
        let store = state.store.read().await;
        if let Some(entry) = store.get(key) {
            if entry.cache.is_running() {
                return;
            }
        }
    }

    let permit = match state.scheduler.semaphore.clone().try_acquire_owned() {
        Ok(p) => p,
        Err(_) => {
            tracing::trace!("no worker permits, skipping execution for '{key}'");
            return;
        }
    };

    let env_snapshot;
    {
        let mut store = state.store.write().await;
        if let Some(entry) = store.get_mut(key) {
            if !entry.cache.start() {
                return;
            }
            env_snapshot = entry.last_env.clone();
        } else {
            return;
        }
    }

    let exec_cwd = if exec_in_cwd {
        env_snapshot.get(ENV_CWD).cloned()
    } else {
        None
    };

    let run = run.to_string();
    let key = key.to_string();
    let state = Arc::clone(state);

    tokio::spawn(async move {
        let _permit = permit;
        let result = run_command(&run, shell, &env_snapshot, timeout, exec_cwd.as_deref()).await;

        let mut store = state.store.write().await;
        if let Some(entry) = store.get_mut(&key) {
            match result {
                Ok(output) => {
                    tracing::debug!("scheduler: '{key}' completed: {output}");
                    entry.cache.complete(output, env_snapshot);
                }
                Err(e) => {
                    tracing::warn!("scheduler: '{key}' failed: {e}");
                    entry.cache.fail(e);
                }
            }
        }
    });
}

/// Run the main command inline (blocking the scheduler loop).
/// Used for watch-triggered executions to prevent feedback loops: the command
/// must finish before we return to `tokio::select!` so we can drain any
/// inotify events it caused.
async fn execute_inline(
    state: &Arc<DaemonState>,
    key: &str,
    run: &str,
    shell: bool,
    timeout: Duration,
    exec_in_cwd: bool,
) {
    // Skip if already running
    {
        let store = state.store.read().await;
        if let Some(entry) = store.get(key) {
            if entry.cache.is_running() {
                return;
            }
        }
    }

    let permit = match state.scheduler.semaphore.clone().try_acquire_owned() {
        Ok(p) => p,
        Err(_) => {
            tracing::trace!("no worker permits, skipping inline execution for '{key}'");
            return;
        }
    };

    let env_snapshot;
    {
        let mut store = state.store.write().await;
        if let Some(entry) = store.get_mut(key) {
            if !entry.cache.start() {
                return;
            }
            env_snapshot = entry.last_env.clone();
        } else {
            return;
        }
    }

    let exec_cwd = if exec_in_cwd {
        env_snapshot.get(ENV_CWD).cloned()
    } else {
        None
    };

    let result = run_command(run, shell, &env_snapshot, timeout, exec_cwd.as_deref()).await;
    drop(permit);

    let mut store = state.store.write().await;
    if let Some(entry) = store.get_mut(key) {
        match result {
            Ok(output) => {
                tracing::debug!("scheduler: '{key}' completed: {output}");
                entry.cache.complete(output, env_snapshot);
            }
            Err(e) => {
                tracing::warn!("scheduler: '{key}' failed: {e}");
                entry.cache.fail(e);
            }
        }
    }
}

/// Run the check command. Returns `true` if its output changed.
async fn run_check(
    state: &Arc<DaemonState>,
    key: &str,
    check_cmd: &str,
    shell: bool,
    timeout: Duration,
    exec_in_cwd: bool,
) -> bool {
    let (env_snapshot, last_output) = {
        let store = state.store.read().await;
        match store.get(key) {
            Some(entry) => (entry.last_env.clone(), entry.last_check_output.clone()),
            None => return false,
        }
    };

    let exec_cwd = if exec_in_cwd {
        env_snapshot.get(ENV_CWD).cloned()
    } else {
        None
    };

    match run_command(check_cmd, shell, &env_snapshot, timeout, exec_cwd.as_deref()).await {
        Ok(output) => {
            let changed = last_output.as_ref() != Some(&output);
            let mut store = state.store.write().await;
            if let Some(entry) = store.get_mut(key) {
                entry.last_check_output = Some(output);
            }
            changed
        }
        Err(e) => {
            tracing::debug!("check command for '{key}' failed: {e}");
            false
        }
    }
}

/// Set up inotify file watchers for the given paths.
///
/// For file paths, watches the parent directory and filters events by filename.
/// This survives atomic file replacement (write temp → rename), which changes
/// the inode and kills a direct file watch. Same pattern as the config watcher.
///
/// For directory paths, watches the directory directly with recursive mode.
async fn setup_file_watcher(
    watch_paths: &[String],
    state: &Arc<DaemonState>,
    key: &str,
    tx: tokio::sync::mpsc::Sender<()>,
) -> Option<RecommendedWatcher> {
    if watch_paths.is_empty() {
        return None;
    }

    let base_dir = {
        let store = state.store.read().await;
        store
            .get(key)
            .and_then(|e| e.last_env.get(ENV_CWD).cloned())
    };

    // Resolve all paths and collect the filenames we need to filter on.
    // For files: we watch the parent dir and filter by filename.
    // For dirs: we watch the dir directly (no filtering needed).
    let mut file_filters: Vec<std::ffi::OsString> = Vec::new();
    let mut watch_targets: Vec<(PathBuf, RecursiveMode)> = Vec::new();

    for path_str in watch_paths {
        let path = if let Some(ref base) = base_dir {
            resolve_watch_path(base, path_str)
        } else {
            PathBuf::from(path_str)
        };

        if path.is_dir() {
            watch_targets.push((path, RecursiveMode::Recursive));
        } else if let Some(parent) = path.parent() {
            // Watch parent directory, filter events by this filename
            if let Some(filename) = path.file_name() {
                file_filters.push(filename.to_os_string());
                // Only add the parent once even if multiple files share it
                let parent_buf = parent.to_path_buf();
                if !watch_targets.iter().any(|(p, _)| p == &parent_buf) {
                    watch_targets.push((parent_buf, RecursiveMode::NonRecursive));
                }
            }
        }
    }

    let mut watcher =
        match notify::recommended_watcher(move |res: Result<notify::Event, notify::Error>| {
            match res {
                Ok(event) => {
                    // If we have file filters, only fire for events that match
                    let dominated = if file_filters.is_empty() {
                        true
                    } else {
                        event.paths.iter().any(|p| {
                            p.file_name()
                                .map_or(false, |name| file_filters.iter().any(|f| f == name))
                        })
                    };
                    if dominated {
                        let _ = tx.try_send(());
                    }
                }
                Err(_) => {
                    let _ = tx.try_send(());
                }
            }
        }) {
            Ok(w) => w,
            Err(e) => {
                tracing::warn!("failed to create file watcher for '{key}': {e}");
                return None;
            }
        };

    for (path, mode) in &watch_targets {
        if let Err(e) = watcher.watch(path, *mode) {
            tracing::warn!("failed to watch '{}' for '{key}': {e}", path.display());
        } else {
            tracing::debug!("watching '{}' for '{key}'", path.display());
        }
    }

    Some(watcher)
}

/// Resolve a relative watch path against a base directory.
///
/// If the path exists directly under `base`, use it. Otherwise, walk up
/// parent directories until the path is found. This handles the common case
/// where CWD is a subdirectory of a git repo and the watch path is something
/// like `.git/HEAD` which only exists at the repo root.
///
/// Falls back to `base/relative` if nothing is found (so the caller gets
/// a clear "not found" error from the watcher).
fn resolve_watch_path(base: &str, relative: &str) -> PathBuf {
    let direct = PathBuf::from(base).join(relative);
    if direct.exists() {
        return direct;
    }

    // Walk up parent directories
    let mut ancestor = PathBuf::from(base);
    for _ in 0..20 {
        if !ancestor.pop() {
            break;
        }
        let candidate = ancestor.join(relative);
        if candidate.exists() {
            tracing::debug!(
                "resolved watch path '{relative}' to '{}' (walked up from '{base}')",
                candidate.display()
            );
            return candidate;
        }
    }

    // Nothing found — return the original so the caller logs a useful error
    direct
}
