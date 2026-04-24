//! Filesystem watcher with debouncing + periodic heartbeat timer.

use anyhow::Result;
use notify::RecursiveMode;
use notify_debouncer_full::{DebouncedEvent, new_debouncer};
use std::path::{Component, Path};
use std::sync::mpsc::{RecvTimeoutError, channel};
use std::time::{Duration, Instant};

pub enum Tick {
    Filesystem,
    Heartbeat,
}

/// Block the calling thread and emit a `Tick` whenever either the
/// filesystem produces debounced events or the heartbeat timer fires.
/// `handler` is called with the reason and must return `Ok(true)` to keep
/// running or `Ok(false)` to exit cleanly.
pub fn run<F>(
    root: &Path,
    debounce: Duration,
    heartbeat: Duration,
    mut handler: F,
) -> Result<()>
where
    F: FnMut(Tick) -> Result<bool>,
{
    let (tx, rx) = channel::<Result<Vec<DebouncedEvent>, Vec<notify::Error>>>();
    let mut debouncer = new_debouncer(debounce, None, move |res| {
        let _ = tx.send(res);
    })?;
    debouncer.watch(root, RecursiveMode::Recursive)?;

    // Initial run: treat startup as a heartbeat.
    if !handler(Tick::Heartbeat)? {
        return Ok(());
    }
    let mut next_heartbeat = Instant::now() + heartbeat;

    loop {
        let now = Instant::now();
        let wait = next_heartbeat.saturating_duration_since(now);
        match rx.recv_timeout(wait) {
            Ok(Ok(events)) => {
                // Filter out events inside dotdirs like `.git` — a git
                // pull churns thousands of object-file writes that we
                // don't care about. Only fire a cycle if at least one
                // event touches a file outside any hidden directory.
                if !events.iter().any(|e| events_path_worth_scanning(&e.paths)) {
                    continue;
                }
                if !handler(Tick::Filesystem)? {
                    return Ok(());
                }
                next_heartbeat = Instant::now() + heartbeat;
            }
            Ok(Err(errs)) => {
                for e in errs {
                    tracing::warn!("watcher error: {e}");
                }
            }
            Err(RecvTimeoutError::Timeout) => {
                if !handler(Tick::Heartbeat)? {
                    return Ok(());
                }
                next_heartbeat = Instant::now() + heartbeat;
            }
            Err(RecvTimeoutError::Disconnected) => {
                anyhow::bail!("watcher channel disconnected");
            }
        }
    }
}

/// True if any path in the event is outside every hidden (`.`-prefixed)
/// directory component. That excludes `.git/…`, `.direnv/…`, etc.
fn events_path_worth_scanning(paths: &[std::path::PathBuf]) -> bool {
    paths.iter().any(|p| {
        !p.components().any(|c| match c {
            Component::Normal(name) => name
                .to_str()
                .map(|s| s.starts_with('.'))
                .unwrap_or(false),
            _ => false,
        })
    })
}
