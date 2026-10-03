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
use regex::Regex;
use sha1::{Digest, Sha1};
use std::collections::HashSet;
use std::path::Path;
use std::sync::LazyLock;

use crate::sync::{Change, ChangeKind};

/// Filename prefixes of renderer output. Only these files are ever cleaned
/// up: marki wrote them, and nothing but a marki-rendered field names them.
const RENDERER_PREFIXES: [&str; 3] = ["marki-map-", "marki-typst-", "marki-media-"];

static RENDERER_SRC: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"src="(marki-(?:map|typst|media)-[^"]+)""#).unwrap());

/// Renderer media files named in a note's field HTML (`src="..."`,
/// attribute-unescaped).
pub fn referenced_names(html: &str) -> impl Iterator<Item = String> + '_ {
    RENDERER_SRC.captures_iter(html).map(|c| {
        c[1].replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
    })
}

/// Live renderer files in `media.db` that nothing references, sorted.
pub fn unused(refs: &HashSet<String>, media_db: &Path) -> Result<Vec<String>> {
    if !media_db.exists() {
        return Ok(Vec::new());
    }
    let db = MediaDatabase::open_or_create(media_db)
        .with_context(|| format!("open media db {}", media_db.display()))?;
    let mut out = Vec::new();
    for p in RENDERER_PREFIXES {
        out.extend(db.live_names_with_prefix(p)?.into_iter().filter(|n| !refs.contains(n)));
    }
    out.sort();
    Ok(out)
}

/// One `MediaDelete` change per unused file.
pub fn delete_changes(names: &[String]) -> Vec<Change> {
    names
        .iter()
        .map(|n| Change {
            kind: ChangeKind::MediaDelete,
            id: n.clone(),
            path: None,
            detail: "no card uses it".into(),
            content_hash: String::new(),
            full_sync: false,
        })
        .collect()
}

/// Tombstone `names` in `media.db` in one transaction (media sync then
/// deletes them on clients), then remove the files. A file that fails to
/// go stays on disk unregistered, which Anki's Check Media reports; the
/// database is what sync follows.
pub fn delete(names: &[String], media_dir: Option<&Path>, media_db: &Path) -> Result<usize> {
    if names.is_empty() {
        return Ok(0);
    }
    let mut db = MediaDatabase::open_or_create(media_db)
        .with_context(|| format!("open media db {}", media_db.display()))?;
    db.transact(|w| {
        for n in names {
            w.remove_file(n).with_context(|| format!("remove media {n}"))?;
        }
        Ok(())
    })?;
    if let Some(dir) = media_dir {
        for n in names {
            match std::fs::remove_file(dir.join(n)) {
                Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                    tracing::warn!(file = n, "remove media file: {e}");
                }
                _ => {}
            }
        }
    }
    Ok(names.len())
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn referenced_names_finds_renderer_files_only() {
        let html = r#"<img src="marki-map-00ff-base.svg"><img src="photo.png">
            <audio src="marki-media-ab12-a&amp;b.mp3"></audio><img src="marki-typst-1234.svg">"#;
        let got: Vec<String> = referenced_names(html).collect();
        assert_eq!(got, ["marki-map-00ff-base.svg", "marki-media-ab12-a&b.mp3", "marki-typst-1234.svg"]);
    }

    #[test]
    fn unused_skips_referenced_foreign_and_deleted_files() {
        let dir = std::env::temp_dir().join(format!("marki-media-unused-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("media.db");
        let _ = std::fs::remove_file(&db_path);
        let media = dir.join("media");
        std::fs::create_dir_all(&media).unwrap();
        let mut db = MediaDatabase::open_or_create(&db_path).unwrap();
        db.transact(|w| {
            for n in ["marki-map-a-base.svg", "marki-map-b-base.svg", "marki-typst-c.svg", "user.png"] {
                w.upsert_file(n, n.as_bytes())?;
            }
            Ok(())
        })
        .unwrap();
        drop(db);
        std::fs::write(media.join("marki-typst-c.svg"), b"x").unwrap();

        let refs: HashSet<String> = ["marki-map-a-base.svg".to_string()].into();
        let unused = unused(&refs, &db_path).unwrap();
        assert_eq!(unused, ["marki-map-b-base.svg", "marki-typst-c.svg"], "user files are never candidates");

        assert_eq!(delete(&unused, Some(&media), &db_path).unwrap(), 2);
        assert!(!media.join("marki-typst-c.svg").exists());
        assert!(super::unused(&refs, &db_path).unwrap().is_empty(), "tombstoned files are gone");
        std::fs::remove_dir_all(&dir).ok();
    }
}
