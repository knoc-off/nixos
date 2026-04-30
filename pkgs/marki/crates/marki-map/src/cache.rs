//! Content-addressable on-disk cache for rendered map assets.
//!
//! Layout:
//!
//! ```text
//! <cache_root>/render/<key>/
//!     <layer>.svg               (one per layer)
//!     sidecar.json
//!     .ready                    (atomic completion marker)
//! ```
//!
//! Readers refuse to use a directory that's missing `.ready`, so a
//! crash mid-write can't be observed as a "successful" cache hit.

use crate::error::MapError;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

/// Marker file that signals "this directory's contents are complete".
const READY_MARKER: &str = ".ready";

/// Compute the directory where a render with `cache_key` lives. Does
/// not create or check the directory.
pub fn render_dir(cache_root: &Path, cache_key: &str) -> PathBuf {
    cache_root.join("render").join(cache_key)
}

/// True if the render directory for `cache_key` exists *and* has a
/// `.ready` marker. False otherwise.
pub fn is_ready(cache_root: &Path, cache_key: &str) -> bool {
    render_dir(cache_root, cache_key).join(READY_MARKER).exists()
}

/// One file to write inside a cache directory.
pub struct CacheFile<'a> {
    pub name: &'a str,
    pub bytes: &'a [u8],
}

/// Atomically populate the cache directory for `cache_key` with the
/// given files. The `.ready` marker is written last; if any earlier
/// step fails, the directory remains in a never-ready state which
/// future readers will treat as a miss.
///
/// If the directory is already ready, this is a no-op.
pub fn write_atomic(
    cache_root: &Path,
    cache_key: &str,
    files: &[CacheFile<'_>],
) -> Result<(), MapError> {
    let dir = render_dir(cache_root, cache_key);
    if dir.join(READY_MARKER).exists() {
        return Ok(());
    }
    fs::create_dir_all(&dir)?;

    for f in files {
        let p = dir.join(f.name);
        // Tempfile + rename so concurrent readers can't see a partial
        // file. Tempfile lives in the same dir to keep the rename
        // atomic on every common filesystem.
        let tmp = dir.join(format!(".{}.tmp", f.name));
        {
            let mut h = fs::File::create(&tmp)?;
            h.write_all(f.bytes)?;
            h.sync_all().ok();
        }
        fs::rename(&tmp, &p)?;
    }

    // Final marker — writing it last is the whole point.
    let marker = dir.join(READY_MARKER);
    let tmp_marker = dir.join(format!(".{READY_MARKER}.tmp"));
    fs::File::create(&tmp_marker)?.sync_all().ok();
    fs::rename(&tmp_marker, &marker)?;

    Ok(())
}

/// Read a single file from a ready cache directory. Returns
/// `Err(MapError::Cache)` if the directory isn't ready.
pub fn read_file(
    cache_root: &Path,
    cache_key: &str,
    name: &str,
) -> Result<Vec<u8>, MapError> {
    if !is_ready(cache_root, cache_key) {
        return Err(MapError::Cache(format!(
            "render dir for {cache_key} is not ready"
        )));
    }
    let p = render_dir(cache_root, cache_key).join(name);
    Ok(fs::read(&p)?)
}

/// List files in a ready cache dir (excluding the marker). Useful when
/// the renderer needs to enumerate every emitted layer.
pub fn list_files(cache_root: &Path, cache_key: &str) -> Result<Vec<String>, MapError> {
    if !is_ready(cache_root, cache_key) {
        return Err(MapError::Cache(format!(
            "render dir for {cache_key} is not ready"
        )));
    }
    let dir = render_dir(cache_root, cache_key);
    let mut out = Vec::new();
    for entry in fs::read_dir(&dir)? {
        let entry = entry?;
        let name = match entry.file_name().into_string() {
            Ok(n) => n,
            Err(_) => continue,
        };
        if name == READY_MARKER || name.starts_with('.') {
            continue;
        }
        out.push(name);
    }
    out.sort();
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static N: AtomicU64 = AtomicU64::new(0);

    fn tempdir() -> PathBuf {
        let p = std::env::temp_dir().join(format!(
            "marki-map-cache-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        p
    }

    #[test]
    fn write_then_read_round_trip() {
        let root = tempdir();
        let key = "abcd1234abcd1234";
        write_atomic(
            &root,
            key,
            &[
                CacheFile {
                    name: "base.svg",
                    bytes: b"<svg/>",
                },
                CacheFile {
                    name: "sidecar.json",
                    bytes: b"{}",
                },
            ],
        )
        .unwrap();

        assert!(is_ready(&root, key));
        let svg = read_file(&root, key, "base.svg").unwrap();
        assert_eq!(svg, b"<svg/>");
        let mut listed = list_files(&root, key).unwrap();
        listed.sort();
        assert_eq!(listed, vec!["base.svg", "sidecar.json"]);
    }

    #[test]
    fn missing_ready_marker_is_not_ready() {
        let root = tempdir();
        let key = "ffffffffffffffff";
        let dir = render_dir(&root, key);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("base.svg"), b"oops").unwrap();
        assert!(!is_ready(&root, key));
        assert!(read_file(&root, key, "base.svg").is_err());
    }

    #[test]
    fn second_write_is_no_op() {
        let root = tempdir();
        let key = "1111111111111111";
        write_atomic(&root, key, &[CacheFile { name: "a", bytes: b"first" }])
            .unwrap();
        write_atomic(&root, key, &[CacheFile { name: "a", bytes: b"second" }])
            .unwrap();
        // First write wins because second is short-circuited.
        let got = read_file(&root, key, "a").unwrap();
        assert_eq!(got, b"first");
    }
}
