//! Filesystem watcher with debouncing + periodic heartbeat timer.

use anyhow::Result;
use notify::RecursiveMode;
use notify::event::EventKind;
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
                // Two filters:
                //
                // 1. Event kind: drop read-only events (Access, Open,
                //    CloseNoWrite) that markid's own scan cycle
                //    generates — opening .md files for parsing fires
                //    IN_OPEN, which would retrigger an immediate cycle,
                //    creating a tight self-feeding loop.
                //
                // 2. Path: drop events inside hidden directories
                //    (.git, .direnv, …) — git operations churn
                //    thousands of object writes we don't care about.
                let dominated = events.iter().any(|e| {
                    is_write_event(&e.event.kind)
                        && events_path_worth_scanning(&e.paths)
                });
                if !dominated {
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

/// True for events that indicate actual content changes: file
/// created, modified, removed, or renamed. False for read-only
/// events (open, access, close-no-write) which markid's own scan
/// cycle generates when it reads `.md` files.
fn is_write_event(kind: &EventKind) -> bool {
    matches!(
        kind,
        EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    )
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

#[cfg(test)]
mod tests {
    use super::*;
    use notify::event::*;

    #[test]
    fn write_events_are_interesting() {
        assert!(is_write_event(&EventKind::Create(CreateKind::File)));
        assert!(is_write_event(&EventKind::Modify(ModifyKind::Data(DataChange::Content))));
        assert!(is_write_event(&EventKind::Modify(ModifyKind::Name(RenameMode::Both))));
        assert!(is_write_event(&EventKind::Remove(RemoveKind::File)));
    }

    #[test]
    fn read_events_are_ignored() {
        assert!(!is_write_event(&EventKind::Access(AccessKind::Open(AccessMode::Read))));
        assert!(!is_write_event(&EventKind::Access(AccessKind::Close(AccessMode::Read))));
        assert!(!is_write_event(&EventKind::Other));
        assert!(!is_write_event(&EventKind::Any));
    }
}
