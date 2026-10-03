//! Media push into the collection's media folder.
//!
//! Renderer-emitted assets (SVGs, audio, etc.) are content-addressed by the
//! renderer, so we trust the filename verbatim. Each asset is written into
//! `<collection>.media/`, the folder an Anki client keeps beside its
//! collection; Anki's media sync notices added and removed files on its next
//! scan and uploads them. No media database is written.

use anyhow::{Context, Result};
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

/// Renderer files in `media_dir` that nothing references, sorted.
pub fn unused(refs: &HashSet<String>, media_dir: &Path) -> Result<Vec<String>> {
    let entries = match std::fs::read_dir(media_dir) {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        r => r.with_context(|| format!("list media dir {}", media_dir.display()))?,
    };
    let mut out = Vec::new();
    for entry in entries {
        let name = entry?.file_name().to_string_lossy().into_owned();
        if RENDERER_PREFIXES.iter().any(|p| name.starts_with(p)) && !refs.contains(&name) {
            out.push(name);
        }
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

/// Remove `names` from the media folder; media sync then deletes them on
/// the server and other clients. Already-missing files count as removed.
pub fn delete(names: &[String], media_dir: &Path) -> Result<usize> {
    for n in names {
        match std::fs::remove_file(media_dir.join(n)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => {
                return Err(e).with_context(|| format!("remove media file {n}"));
            }
            _ => {}
        }
    }
    Ok(names.len())
}

/// Assets missing from, or different in, the media folder: one `Media`
/// change each.
pub fn plan(assets: &[Asset], media_dir: &Path) -> Vec<Change> {
    let mut out = Vec::new();
    for a in assets {
        let detail = match std::fs::read(media_dir.join(&a.filename)) {
            Ok(b) if b == a.bytes => continue,
            Ok(_) => "changed",
            Err(_) => "new",
        };
        out.push(Change {
            kind: ChangeKind::Media,
            id: a.filename.clone(),
            path: None,
            detail: format!("{detail} ({} bytes)", a.bytes.len()),
            content_hash: hex(&Sha1::digest(&a.bytes)),
            full_sync: false,
        });
    }
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

/// Write every asset into the media folder, skipping files that already
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
    fn plan_write_unused_delete_round_trip() {
        let dir = std::env::temp_dir().join(format!("marki-media-rt-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let asset = |n: &str, b: &[u8]| Asset {
            filename: n.into(),
            bytes: b.to_vec(),
            mime: marki_render::AssetMime::SvgXml,
        };
        let assets = [asset("marki-map-a-base.svg", b"a"), asset("marki-typst-c.svg", b"c")];

        assert_eq!(plan(&assets, &dir).len(), 2, "missing folder: everything is new");
        assert_eq!(write_files(&assets, &dir).unwrap(), 2);
        assert!(plan(&assets, &dir).is_empty(), "written files match");
        std::fs::write(dir.join("marki-typst-c.svg"), b"old").unwrap();
        assert_eq!(plan(&assets, &dir)[0].detail, "changed (1 bytes)");
        write_files(&assets, &dir).unwrap();

        std::fs::write(dir.join("marki-map-b-base.svg"), b"b").unwrap();
        std::fs::write(dir.join("user.png"), b"u").unwrap();
        let refs: HashSet<String> = ["marki-map-a-base.svg".to_string()].into();
        let unused = unused(&refs, &dir).unwrap();
        assert_eq!(unused, ["marki-map-b-base.svg", "marki-typst-c.svg"], "user files are never candidates");
        assert_eq!(delete(&unused, &dir).unwrap(), 2);
        assert!(super::unused(&refs, &dir).unwrap().is_empty());
        assert!(dir.join("user.png").exists());
        std::fs::remove_dir_all(&dir).ok();
    }
}
