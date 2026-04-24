//! Atomic rewrite of a card's `.md` file in canonical format.

use anyhow::{Context, Result};
use marki_core::render::format_card;
use marki_core::tag::NoteId;
use std::fs;
use std::io::Write;
use std::path::Path;

/// Format `path` in place. If the file has no `#id(...)` yet, use
/// `minted_id`; otherwise keep the existing id.
///
/// Writes via tempfile + atomic rename on the same directory to avoid
/// torn writes. No-op if the file is already in canonical form.
pub fn write_back(path: &Path, minted_id: &NoteId) -> Result<()> {
    let source = fs::read_to_string(path)
        .with_context(|| format!("read {}", path.display()))?;
    let new_source = format_card(&source, minted_id);
    if new_source == source {
        return Ok(());
    }

    let dir = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("file has no parent: {}", path.display()))?;
    let file_name = path
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("file has no name: {}", path.display()))?;
    let tmp_name = format!(".{}.markid.tmp", file_name.to_string_lossy());
    let tmp_path = dir.join(&tmp_name);

    {
        let mut f = fs::File::create(&tmp_path)
            .with_context(|| format!("create tempfile {}", tmp_path.display()))?;
        f.write_all(new_source.as_bytes())
            .with_context(|| format!("write tempfile {}", tmp_path.display()))?;
        f.sync_all().ok();
    }
    fs::rename(&tmp_path, path)
        .with_context(|| format!("rename {} -> {}", tmp_path.display(), path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static N: AtomicU64 = AtomicU64::new(0);

    fn tempdir() -> std::path::PathBuf {
        let base = std::env::temp_dir().join(format!(
            "markid-test-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst),
        ));
        let _ = fs::remove_dir_all(&base);
        fs::create_dir_all(&base).unwrap();
        base
    }

    #[test]
    fn writes_id_line_into_unmarked_file() {
        let tmp = tempdir();
        let p = tmp.join("a.md");
        fs::write(&p, "front\n---\nback\n").unwrap();
        write_back(&p, &"abcd1234".to_string()).unwrap();
        let got = fs::read_to_string(&p).unwrap();
        assert!(got.trim_end().ends_with("#id(abcd1234)"));
    }

    #[test]
    fn idempotent_rewrite() {
        let tmp = tempdir();
        let p = tmp.join("b.md");
        fs::write(&p, "body\n").unwrap();
        write_back(&p, &"x".to_string()).unwrap();
        let first = fs::read_to_string(&p).unwrap();
        write_back(&p, &"x".to_string()).unwrap();
        let second = fs::read_to_string(&p).unwrap();
        assert_eq!(first, second);
    }

    #[test]
    fn collects_tags_to_end() {
        let tmp = tempdir();
        let p = tmp.join("c.md");
        fs::write(&p, "#cloze\n\nbody\n\n#foo\n").unwrap();
        write_back(&p, &"idX".to_string()).unwrap();
        let got = fs::read_to_string(&p).unwrap();
        assert_eq!(got, "body\n\n#id(idX) #cloze #foo\n");
    }
}
