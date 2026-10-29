//! Sync marki's local collection with an Anki sync server.
//!
//! The protocol is Anki's own: `sync.py` drives Anki's Python library
//! (`anki` on `$MARKI_PYTHON`'s path, pinned by the Nix wrapper to the
//! server's Anki version). The collection must be closed while it runs --
//! Anki opens it exclusively.

use anyhow::{Context, Result, bail};
use std::path::Path;
use std::process::Command;

use crate::config::SyncConfig;

const SCRIPT: &str = include_str!("sync.py");
const DECK_OPTIONS: &str = include_str!("deck_options.py");

#[derive(Clone, Copy)]
pub enum Mode {
    /// Before marki writes: fetch what other devices changed.
    Pull,
    /// After marki wrote: send its changes.
    Push { allow_upload: bool },
}

/// What the sync did: `normal`, `download` (the local copy was replaced by
/// the server's) or `upload` (the server's was replaced by ours).
pub fn sync(cfg: &SyncConfig, collection: &Path, mode: Mode) -> Result<String> {
    if let Some(dir) = collection.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("create {}", dir.display()))?;
    }
    let (mode, allow_upload) = match mode {
        Mode::Pull => ("pull", false),
        Mode::Push { allow_upload } => ("push", allow_upload),
    };
    let req = serde_json::json!({
        "collection": collection,
        "endpoint": cfg.endpoint,
        "username": cfg.username,
        "password_file": cfg.password_file,
        "mode": mode,
        "allow_upload": allow_upload,
    });
    let res = run(SCRIPT, &req).map_err(|e| anyhow::anyhow!("sync with {} failed: {e}", cfg.endpoint))?;
    Ok(res["action"].as_str().unwrap_or("?").to_string())
}

/// Read (`action: get`) or change (`set`) deck options in the local
/// collection; see `deck_options.py` for the request. Doesn't sync.
pub fn deck_options(collection: &Path, mut req: serde_json::Value) -> Result<serde_json::Value> {
    req["collection"] = serde_json::json!(collection);
    run(DECK_OPTIONS, &req)
}

/// Run one of the Anki-library scripts with a JSON request; its one JSON
/// result line, or its last stderr line as the error.
fn run(script: &str, req: &serde_json::Value) -> Result<serde_json::Value> {
    let python = std::env::var_os("MARKI_PYTHON")
        .context("MARKI_PYTHON is not set; it must name a python with Anki's `anki` library")?;
    let out = Command::new(&python)
        .args(["-c", script, &req.to_string()])
        .output()
        .with_context(|| format!("run {}", python.to_string_lossy()))?;
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        bail!("{}", last_line(&stderr));
    }
    for line in stderr.lines().filter(|l| !l.trim().is_empty()) {
        tracing::info!("anki: {line}");
    }
    serde_json::from_slice(&out.stdout)
        .with_context(|| format!("anki script printed {:?}", String::from_utf8_lossy(&out.stdout)))
}

/// Python tracebacks end with the exception; that line is the useful one.
fn last_line(s: &str) -> &str {
    s.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("no output").trim()
}
