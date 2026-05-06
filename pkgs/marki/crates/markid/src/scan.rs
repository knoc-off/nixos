//! Scan a directory of markdown cards, respecting `.gitignore`.
//!
//! Uses the `ignore` crate (same engine as ripgrep) so we get `.gitignore`,
//! `.ignore`, global git excludes, and hidden-file filtering for free.

use anyhow::{Context, Result};
use ignore::WalkBuilder;
use marki_core::note::Note;
use marki_core::note_parser::parse_note;
use std::path::{Path, PathBuf};

/// A scanned note (structural parser pipeline).
pub struct ScannedNote {
    pub path: PathBuf,
    pub source: String,
    pub note: Note,
}

/// Scan a directory of markdown files, producing structural `Note` objects.
pub fn scan_dir_v2(root: &Path) -> Result<Vec<ScannedNote>> {
    let mut out = Vec::new();
    for path in walk_md_files(root) {
        let source = std::fs::read_to_string(&path)
            .with_context(|| format!("read {}", path.display()))?;
        let note = parse_note(&source, path.clone());
        out.push(ScannedNote { path, source, note });
    }
    Ok(out)
}

/// Walk a directory tree returning all `.md`/`.markdown` file paths.
fn walk_md_files(root: &Path) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    for dent in WalkBuilder::new(root)
        .standard_filters(true)
        .follow_links(false)
        .build()
    {
        let entry = match dent {
            Ok(e) => e,
            Err(e) => {
                tracing::warn!("walk error: {e}");
                continue;
            }
        };
        if !entry.file_type().is_some_and(|t| t.is_file()) {
            continue;
        }
        let path = entry.path();
        if !path
            .extension()
            .is_some_and(|e| e == "md" || e == "markdown")
        {
            continue;
        }
        paths.push(path.to_path_buf());
    }
    paths
}

/// Derive Anki deck path from a card file's location relative to the scan
/// root. `math/algebra/foo.md` rooted at `./cards/` → `"math::algebra"`. A
/// file at the root returns `"Default"`.
pub fn deck_for(root: &Path, file: &Path) -> String {
    let rel = match file.strip_prefix(root) {
        Ok(r) => r,
        Err(_) => return "Default".into(),
    };
    let mut parts: Vec<&str> = rel
        .parent()
        .into_iter()
        .flat_map(|p| p.components())
        .filter_map(|c| match c {
            std::path::Component::Normal(s) => s.to_str(),
            _ => None,
        })
        .collect();
    if parts.is_empty() {
        "Default".into()
    } else {
        // Trim any trailing empty components (shouldn't happen, but safe).
        parts.retain(|p| !p.is_empty());
        if parts.is_empty() {
            "Default".into()
        } else {
            parts.join("::")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn root_level_file_goes_to_default() {
        let root = PathBuf::from("/cards");
        let file = PathBuf::from("/cards/foo.md");
        assert_eq!(deck_for(&root, &file), "Default");
    }

    #[test]
    fn single_level() {
        let root = PathBuf::from("/cards");
        let file = PathBuf::from("/cards/math/foo.md");
        assert_eq!(deck_for(&root, &file), "math");
    }

    #[test]
    fn nested() {
        let root = PathBuf::from("/cards");
        let file = PathBuf::from("/cards/math/algebra/foo.md");
        assert_eq!(deck_for(&root, &file), "math::algebra");
    }

    #[test]
    fn outside_root_is_default() {
        let root = PathBuf::from("/cards");
        let file = PathBuf::from("/elsewhere/foo.md");
        assert_eq!(deck_for(&root, &file), "Default");
    }
}
