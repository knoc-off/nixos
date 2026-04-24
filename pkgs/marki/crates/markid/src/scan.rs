//! Scan a directory of markdown cards, respecting `.gitignore`.
//!
//! Uses the `ignore` crate (same engine as ripgrep) so we get `.gitignore`,
//! `.ignore`, global git excludes, and hidden-file filtering for free.

use anyhow::{Context, Result};
use ignore::WalkBuilder;
use marki_core::parser::{ParseOutput, parse};
use std::path::{Path, PathBuf};

pub struct ScannedCard {
    pub path: PathBuf,
    pub source: String,
    pub parsed: ParseOutput,
}

pub fn scan_dir(root: &Path) -> Result<Vec<ScannedCard>> {
    let mut out = Vec::new();
    for dent in WalkBuilder::new(root)
        .standard_filters(true) // .gitignore, .ignore, hidden files
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
        let source = std::fs::read_to_string(path)
            .with_context(|| format!("read {}", path.display()))?;
        let parsed = parse(&source);
        out.push(ScannedCard {
            path: path.to_path_buf(),
            source,
            parsed,
        });
    }
    Ok(out)
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
