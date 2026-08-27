//! On-disk record of what actually went upstream.
//!
//! The point of this proxy is that its output is indistinguishable from
//! real Claude Code's. That is only checkable against a byte-level record
//! of the request we sent, so this writes one JSON file per exchange,
//! diffable against a capture from the real CLI.
//!
//! Off unless `--dump-dir` is set: the records contain full prompts and
//! conversation history.

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use axum::http::HeaderMap;
use serde_json::{json, Value};

/// Headers whose values are credentials, not shape.
const REDACTED: &[&str] = &["authorization", "x-api-key"];

pub struct Dumper {
    dir: Option<PathBuf>,
    seq: AtomicU64,
}

/// One upstream exchange, as recorded.
pub struct Record<'a> {
    /// Body as the client sent it.
    pub inbound: &'a Value,
    /// Body after shaping — this is the part that has to match real CC.
    pub outbound: &'a Value,
    pub headers: &'a HeaderMap,
    pub status: u16,
    /// Upstream body, present only for errors. Successful responses are
    /// streamed to the client and never buffered.
    pub error_body: Option<&'a str>,
}

impl Dumper {
    pub fn new(dir: Option<PathBuf>) -> Self {
        Self {
            dir,
            seq: AtomicU64::new(0),
        }
    }

    pub fn enabled(&self) -> bool {
        self.dir.is_some()
    }

    /// Write one record. Dump failures are warnings: losing debug output
    /// is not a reason to fail a request that upstream already answered.
    pub fn write(&self, record: Record<'_>) {
        let Some(dir) = &self.dir else { return };

        let seq = self.seq.fetch_add(1, Ordering::Relaxed);
        let body = json!({
            "seq": seq,
            "status": record.status,
            "request_headers": headers_to_json(record.headers),
            "inbound": record.inbound,
            "outbound": record.outbound,
            "error_body": record.error_body,
        });

        let path = dir.join(format!("{seq:04}.json"));
        let result = std::fs::create_dir_all(dir)
            .and_then(|()| serde_json::to_vec_pretty(&body).map_err(std::io::Error::from))
            .and_then(|bytes| std::fs::write(&path, bytes));

        match result {
            Ok(()) => tracing::debug!(path = %path.display(), "wrote request dump"),
            Err(e) => tracing::warn!(error = %e, path = %path.display(), "failed to write request dump"),
        }
    }
}

fn headers_to_json(headers: &HeaderMap) -> Value {
    let entries = headers.iter().map(|(name, value)| {
        let rendered = if REDACTED.contains(&name.as_str()) {
            "<redacted>".to_string()
        } else {
            value.to_str().unwrap_or("<non-utf8>").to_string()
        };
        (name.as_str().to_string(), Value::String(rendered))
    });
    Value::Object(entries.collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    #[test]
    fn credentials_are_redacted_but_shape_headers_are_not() {
        let mut headers = HeaderMap::new();
        headers.insert("authorization", HeaderValue::from_static("Bearer secret"));
        headers.insert("x-app", HeaderValue::from_static("cli"));

        let json = headers_to_json(&headers);
        assert_eq!(json["authorization"], "<redacted>");
        assert_eq!(json["x-app"], "cli");
    }

    #[test]
    fn disabled_dumper_writes_nothing() {
        let dumper = Dumper::new(None);
        assert!(!dumper.enabled());
        dumper.write(Record {
            inbound: &json!({}),
            outbound: &json!({}),
            headers: &HeaderMap::new(),
            status: 200,
            error_body: None,
        });
    }
}
