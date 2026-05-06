//! Media push via AnkiConnect `storeMediaFile`.

use anyhow::{Context, Result};
use base64::Engine;
use marki_core::EmittedAsset;

use crate::anki::AnkiConnect;

/// Push an [`EmittedAsset`] (produced by an external block renderer)
/// into Anki's media collection. The renderer is responsible for picking
/// a content-addressed `filename`; we trust it verbatim and let Anki
/// dedup by name.
pub fn push_emitted(anki: &AnkiConnect, asset: &EmittedAsset) -> Result<String> {
    let b64 = base64::engine::general_purpose::STANDARD.encode(&asset.bytes);
    let stored = anki
        .store_media_file(&asset.filename, &b64)
        .with_context(|| format!("storeMediaFile {}", asset.filename))?;
    Ok(stored)
}
