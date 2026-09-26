//! Media push into the server-side media store.
//!
//! Renderer-emitted assets (SVGs, audio, etc.) are content-addressed by the
//! renderer, so we trust the filename verbatim. Each asset is written to the
//! collection's `media/` directory and recorded in the `media.db` (schema v4)
//! that sits beside `collection.anki2`, exactly as anki-sync-server keeps it.
//! A file only reaches clients once it is in *both*: the directory holds the
//! bytes, the database row is what media sync announces.

use anyhow::{Context, Result};
use marki_anki::media::MediaDatabase;
use marki_render::Asset;
use sha1::{Digest, Sha1};
use std::path::Path;

use crate::sync::{Change, ChangeKind};

/// Assets that are missing from, or differ in, the media store: one
/// `Media` change each. Reads `media.db` (a snapshot when the live file is
/// locked -- the caller decides) and the files in `media_dir`.
pub fn plan(assets: &[Asset], media_dir: &Path, media_db: &Path) -> Result<Vec<Change>> {
    let db = if media_db.exists() {
        Some(MediaDatabase::open_or_create(media_db)
            .with_context(|| format!("open media db {}", media_db.display()))?)
    } else {
        None
    };
    let mut out = Vec::new();
    for a in assets {
        let csum = Sha1::digest(&a.bytes).to_vec();
        let registered = match &db {
            Some(db) => db
                .entry(&a.filename)?
                .is_some_and(|(c, size)| size > 0 && c == csum),
            None => false,
        };
        let on_disk = std::fs::read(media_dir.join(&a.filename)).is_ok_and(|b| b == a.bytes);
        let detail = match (on_disk, registered) {
            (true, true) => continue,
            (true, false) => "file present but not registered in media.db",
            (false, true) => "registered but file missing or different",
            (false, false) => "new",
        };
        out.push(Change {
            kind: ChangeKind::Media,
            id: a.filename.clone(),
            path: None,
            detail: format!("{detail} ({} bytes)", a.bytes.len()),
            content_hash: hex(&csum),
            full_sync: false,
        });
    }
    out.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(out)
}

/// Write every asset into the media directory, skipping files that already
/// hold the same bytes. Returns how many were written.
pub fn write_files(assets: &[Asset], media_dir: &Path) -> Result<usize> {
    std::fs::create_dir_all(media_dir)
        .with_context(|| format!("create media dir {}", media_dir.display()))?;
    let mut n = 0;
    for a in assets {
        let dest = media_dir.join(&a.filename);
        if std::fs::read(&dest).is_ok_and(|b| b == a.bytes) {
            continue;
        }
        std::fs::write(&dest, &a.bytes)
            .with_context(|| format!("write media file {}", dest.display()))?;
        n += 1;
    }
    Ok(n)
}

/// Record every asset in the media database, in one transaction. Unchanged
/// rows are skipped by the writer, so re-running does not churn usns.
pub fn register(assets: &[Asset], media_db: &Path) -> Result<()> {
    let mut db = MediaDatabase::open_or_create(media_db)
        .with_context(|| format!("open media db {}", media_db.display()))?;
    db.transact(|w| {
        for a in assets {
            w.upsert_file(&a.filename, &a.bytes)
                .with_context(|| format!("record media {}", a.filename))?;
        }
        Ok(())
    })
}

/// Files first, then the database: a failure in between leaves at worst
/// unregistered files, which `plan` reports and the next push registers.
pub fn push_all(assets: &[Asset], media_dir: &Path, media_db: &Path) -> Result<usize> {
    if assets.is_empty() {
        return Ok(0);
    }
    let n = write_files(assets, media_dir)?;
    register(assets, media_db)?;
    Ok(n)
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
