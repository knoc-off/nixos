//! Session-based transaction logger.
//!
//! Writes one JSONL line per request/response transaction to a per-session
//! file under `$XDG_STATE_HOME/compat-proxy/sessions/<session_id>.jsonl`.
//!
//! Each line captures the full request/response cycle:
//! - The parsed inbound request
//! - A JSON Patch (RFC 6902) describing the translation we applied
//! - A human-readable summary of the changes
//! - Redacted upstream headers we sent
//! - Upstream status, response body (or SSE event sequence)
//! - Reverse-translation patch + summary for the response
//! - Any warnings or errors
//!
//! This replaces the old per-request `/tmp/proxy-*.json` dump format.

use std::fs::{File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use serde::Serialize;
use serde_json::Value;

/// One open session log file. Cheap to clone (just an `Arc`).
#[derive(Clone)]
pub struct SessionLogger {
    inner: Arc<Mutex<BufWriter<File>>>,
    path: PathBuf,
}

impl SessionLogger {
    /// Open (or create + append) the per-session log file.
    pub fn open(path: PathBuf) -> std::io::Result<Self> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let mut opts = OpenOptions::new();
        opts.append(true).create(true);

        // Owner-only on unix.
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }

        let file = opts.open(&path)?;
        Ok(Self {
            inner: Arc::new(Mutex::new(BufWriter::new(file))),
            path,
        })
    }

    /// Path of the log file (for startup logging).
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Begin a new transaction. The returned builder accumulates fields
    /// and writes one line on `finish()`.
    pub fn begin(&self) -> TransactionBuilder {
        TransactionBuilder::new(self.clone())
    }

    /// Write one finalized transaction line.
    fn write_line(&self, txn: &Transaction) {
        let json = match serde_json::to_string(txn) {
            Ok(s) => s,
            Err(e) => {
                tracing::warn!("session log: failed to serialize transaction: {e}");
                return;
            }
        };

        let mut guard = match self.inner.lock() {
            Ok(g) => g,
            Err(e) => {
                tracing::warn!("session log: mutex poisoned: {e}");
                return;
            }
        };

        if let Err(e) = writeln!(guard, "{json}") {
            tracing::warn!("session log: write failed: {e}");
            return;
        }
        if let Err(e) = guard.flush() {
            tracing::warn!("session log: flush failed: {e}");
        }
    }
}

/// Resolve the default session log directory using XDG conventions.
///
/// Order: `$XDG_STATE_HOME/compat-proxy/sessions` →
///        `$HOME/.local/state/compat-proxy/sessions` →
///        `/tmp/compat-proxy/sessions`.
pub fn default_log_dir() -> PathBuf {
    if let Ok(state) = std::env::var("XDG_STATE_HOME") {
        if !state.is_empty() {
            return PathBuf::from(state).join("compat-proxy").join("sessions");
        }
    }
    if let Ok(home) = std::env::var("HOME") {
        if !home.is_empty() {
            return PathBuf::from(home)
                .join(".local")
                .join("state")
                .join("compat-proxy")
                .join("sessions");
        }
    }
    PathBuf::from("/tmp/compat-proxy/sessions")
}

/// Accumulator for one transaction. Writes a JSONL line on `finish()`.
///
/// Consumers fill in fields as the request flows through the proxy. SSE
/// streaming requires sharing the builder via `Arc<Mutex<...>>` so the
/// stream task can append events as they arrive.
pub struct TransactionBuilder {
    logger: SessionLogger,
    started_at: Instant,
    txn: Transaction,
    finished: bool,
}

impl TransactionBuilder {
    fn new(logger: SessionLogger) -> Self {
        let txn = Transaction {
            ts: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            txn_id: uuid::Uuid::new_v4().to_string(),
            duration_ms: 0,
            client_ip: None,
            raw_body: None,
            parse_error: None,
            request: None,
            request_patch: None,
            request_changes: Vec::new(),
            upstream_url: None,
            upstream_headers: serde_json::Map::new(),
            upstream_status: None,
            response: None,
            response_patch: None,
            response_changes: Vec::new(),
            sse_events: None,
            warnings: Vec::new(),
            error: None,
        };
        Self {
            logger,
            started_at: Instant::now(),
            txn,
            finished: false,
        }
    }

    pub fn txn_id(&self) -> &str {
        &self.txn.txn_id
    }

    pub fn set_client_ip(&mut self, ip: String) {
        self.txn.client_ip = Some(ip);
    }

    pub fn set_raw_body(&mut self, bytes: &[u8]) {
        // Always store as utf-8 if valid; otherwise fall back to base64.
        match std::str::from_utf8(bytes) {
            Ok(s) => self.txn.raw_body = Some(s.to_string()),
            Err(_) => self.txn.raw_body = Some(format!("<binary {} bytes>", bytes.len())),
        }
    }

    pub fn set_parse_error(&mut self, msg: String) {
        self.txn.parse_error = Some(msg);
    }

    /// Record the parsed (pre-translation) request.
    pub fn set_request<T: Serialize>(&mut self, req: &T) {
        if let Ok(v) = serde_json::to_value(req) {
            self.txn.request = Some(v);
        }
    }

    /// Compute and record the request translation patch + change list.
    /// Pass the post-translation request and the human-readable changes.
    pub fn set_request_translation<T: Serialize>(&mut self, translated: &T, changes: Vec<String>) {
        let translated_v = match serde_json::to_value(translated) {
            Ok(v) => v,
            Err(_) => return,
        };
        if let Some(ref before) = self.txn.request {
            let patch = json_patch::diff(before, &translated_v);
            if let Ok(patch_v) = serde_json::to_value(&patch) {
                self.txn.request_patch = Some(patch_v);
            }
        }
        self.txn.request_changes = changes;
    }

    pub fn set_upstream_url(&mut self, url: String) {
        self.txn.upstream_url = Some(url);
    }

    /// Record one upstream request header. `authorization` is auto-redacted.
    pub fn add_upstream_header(&mut self, name: &str, value: &str) {
        let lower = name.to_ascii_lowercase();
        let redacted = match lower.as_str() {
            "authorization" => "<redacted>".to_string(),
            "x-api-key" => "<redacted>".to_string(),
            _ => value.to_string(),
        };
        self.txn.upstream_headers.insert(lower, Value::String(redacted));
    }

    pub fn set_upstream_status(&mut self, status: u16) {
        self.txn.upstream_status = Some(status);
    }

    /// Record the (already reverse-translated) response and its patch+changes.
    /// `original` is what came back from upstream, `translated` is what we
    /// returned to the client.
    pub fn set_response_translation<T: Serialize>(
        &mut self,
        original: &T,
        translated: &T,
        changes: Vec<String>,
    ) {
        let original_v = match serde_json::to_value(original) {
            Ok(v) => v,
            Err(_) => return,
        };
        let translated_v = match serde_json::to_value(translated) {
            Ok(v) => v,
            Err(_) => return,
        };
        let patch = json_patch::diff(&original_v, &translated_v);
        if let Ok(patch_v) = serde_json::to_value(&patch) {
            self.txn.response_patch = Some(patch_v);
        }
        self.txn.response = Some(translated_v);
        self.txn.response_changes = changes;
    }

    /// Append one reverse-translated SSE event.
    pub fn push_sse_event(&mut self, event_type: &str, data: Value) {
        let entry = self
            .txn
            .sse_events
            .get_or_insert_with(Vec::new);
        entry.push(serde_json::json!({
            "event": event_type,
            "data": data,
        }));
    }

    /// Record a stream-time change (reverse rename, etc.) so the line
    /// reflects what the SSE handler actually did.
    pub fn add_response_change(&mut self, change: String) {
        self.txn.response_changes.push(change);
    }

    pub fn add_warning(&mut self, warning: String) {
        self.txn.warnings.push(warning);
    }

    pub fn set_error(&mut self, error: String) {
        self.txn.error = Some(error);
    }

    /// Write the line. Idempotent — repeated calls are no-ops.
    pub fn finish(mut self) {
        if self.finished {
            return;
        }
        self.finished = true;
        self.txn.duration_ms = self.started_at.elapsed().as_millis() as u64;
        self.logger.write_line(&self.txn);
    }
}

impl Drop for TransactionBuilder {
    fn drop(&mut self) {
        // If finish() wasn't called (panic, early return), still write
        // what we have so debugging mid-flight failures is possible.
        if !self.finished {
            self.txn.duration_ms = self.started_at.elapsed().as_millis() as u64;
            if self.txn.error.is_none() {
                self.txn.error = Some("transaction dropped without finish()".to_string());
            }
            self.logger.write_line(&self.txn);
        }
    }
}

/// One JSONL line. All optional fields are omitted from the output when
/// `None` to keep lines lean.
#[derive(Serialize)]
struct Transaction {
    ts: String,
    txn_id: String,
    duration_ms: u64,

    #[serde(skip_serializing_if = "Option::is_none")]
    client_ip: Option<String>,

    // Failure path: the raw bytes + parse error. Only set when parsing
    // failed before we could populate `request`.
    #[serde(skip_serializing_if = "Option::is_none")]
    raw_body: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    parse_error: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    request: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    request_patch: Option<Value>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    request_changes: Vec<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    upstream_url: Option<String>,
    #[serde(skip_serializing_if = "serde_json::Map::is_empty")]
    upstream_headers: serde_json::Map<String, Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    upstream_status: Option<u16>,

    #[serde(skip_serializing_if = "Option::is_none")]
    response: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_patch: Option<Value>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    response_changes: Vec<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    sse_events: Option<Vec<Value>>,

    #[serde(skip_serializing_if = "Vec::is_empty")]
    warnings: Vec<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}
