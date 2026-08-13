//! Media push into the server-side media store.
//!
//! Renderer-emitted assets (SVGs, audio, etc.) are content-addressed by the
//! renderer, so we trust the filename verbatim. Each asset is written to the
//! collection's `media/` directory and recorded in the `media.db` (schema v4)
//! that sits beside `collection.anki2`, exactly as anki-sync-server keeps it.

use anyhow::{Context, Result};
use marki_anki::media::MediaDatabase;
use marki_render::Asset;
use std::path::Path;

/// Persist every asset in `assets` (deduplicated by filename) into the media
/// directory and media database. Writing the files and the database rows is
/// idempotent: an unchanged file re-hashes to the same csum and is skipped by
/// the writer. Returns nothing; callers surface individual failures.
pub fn push_all(assets: &[Asset], media_dir: &Path, media_db_path: &Path) -> Result<()> {
    if assets.is_empty() {
        return Ok(());
    }
    std::fs::create_dir_all(media_dir)
        .with_context(|| format!("create media dir {}", media_dir.display()))?;
    for a in assets {
        let dest = media_dir.join(&a.filename);
        std::fs::write(&dest, &a.bytes)
            .with_context(|| format!("write media file {}", dest.display()))?;
    }
    let mut db = MediaDatabase::open_or_create(media_db_path)
        .with_context(|| format!("open media db {}", media_db_path.display()))?;
    db.transact(|w| {
        for a in assets {
            w.upsert_file(&a.filename, &a.bytes)
                .with_context(|| format!("record media {}", a.filename))?;
        }
        Ok(())
    })
}
