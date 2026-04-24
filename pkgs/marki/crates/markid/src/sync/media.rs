//! Media push via AnkiConnect `storeMediaFile`.
//!
//! Resolution order:
//!   1. path relative to the `.md` file (e.g. `![](./diagram.png)`)
//!   2. `<root>/media/<basename>` fallback for flat layouts
//!
//! The stored filename is content-addressed (`<first 8 hex of blake3>-<basename>`)
//! so two cards referencing the same logical file don't clobber each other
//! and don't have to coordinate on naming.

use anyhow::{Context, Result};
use base64::Engine;
use std::path::{Path, PathBuf};

use crate::anki::AnkiConnect;

pub fn resolve(root: &Path, md_file: &Path, src: &str) -> Option<PathBuf> {
    // Absolute or already-resolved paths — accept verbatim if they exist.
    let as_is = PathBuf::from(src);
    if as_is.is_absolute() && as_is.exists() {
        return Some(as_is);
    }
    // Relative to the .md file.
    if let Some(parent) = md_file.parent() {
        let cand = parent.join(src);
        if cand.exists() {
            return Some(cand);
        }
    }
    // Fallback: <root>/media/<basename>
    let basename = Path::new(src).file_name()?;
    let cand = root.join("media").join(basename);
    if cand.exists() {
        return Some(cand);
    }
    None
}

pub fn content_addressed_name(path: &Path) -> Result<String> {
    let bytes = std::fs::read(path)
        .with_context(|| format!("read media {}", path.display()))?;
    let hash = blake3::hash(&bytes);
    let hex = hash.to_hex();
    let short = &hex.as_str()[..8];
    let basename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("file");
    Ok(format!("{short}-{basename}"))
}

pub fn push_media(anki: &AnkiConnect, path: &Path) -> Result<String> {
    let name = content_addressed_name(path)?;
    let bytes = std::fs::read(path)
        .with_context(|| format!("read media {}", path.display()))?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    let stored = anki
        .store_media_file(&name, &b64)
        .with_context(|| format!("storeMediaFile {}", name))?;
    Ok(stored)
}
