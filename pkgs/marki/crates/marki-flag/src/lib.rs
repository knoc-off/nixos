//! `marki-flag` — render `flag` blocks to embedded SVG images.
//!
//! Implements `marki_core::BlockRenderer` for the lang token `flag`.
//! See `dsl.rs` for the TOML body format.
//!
//! The renderer supports multiple named flag sources. The `flag` field
//! in the DSL can optionally prefix a source name to target a specific
//! collection:
//!
//!   - `flag = "circle/de"` → look up `de.svg` in the "circle" source
//!   - `flag = "flags/de/by"` → look up `de/by.svg` in the "flags" source
//!   - `flag = "de"` → search all sources in order, first match wins
//!
//! SVGs are base64-encoded into `<img>` data URIs to prevent SVG
//! internal `id` collisions when multiple flags appear in the same
//! Anki session.

pub mod dsl;
pub mod error;

use std::path::{Path, PathBuf};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as BASE64;
use marki_core::{BlockError, BlockRenderer, RenderCtx, RenderedBlock};

pub use error::FlagError;

/// Lang token this renderer handles: `flag`.
pub const FLAG_LANG: &str = "flag";

/// Flag block renderer with multiple named sources.
///
/// Sources are searched in order — the first match wins when no
/// explicit source prefix is given in the DSL.
pub struct FlagRenderer {
    /// Named sources in priority order: `(name, directory)`.
    sources: Vec<(String, PathBuf)>,
}

impl FlagRenderer {
    pub fn new(sources: Vec<(String, PathBuf)>) -> Self {
        Self { sources }
    }
}

impl BlockRenderer for FlagRenderer {
    fn lang(&self) -> &'static str {
        FLAG_LANG
    }

    fn render(&self, src: &str, _ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError> {
        let spec = dsl::parse_flag_spec(src).map_err(|e| BlockError::Parse(e.to_string()))?;
        Ok(render_flag(&self.sources, &spec)?)
    }
}

fn render_flag(
    sources: &[(String, PathBuf)],
    spec: &dsl::FlagSpec,
) -> Result<RenderedBlock, FlagError> {
    let svg_path = resolve(&spec.flag, sources)?;
    let svg_bytes = std::fs::read(&svg_path)?;
    let b64 = BASE64.encode(&svg_bytes);

    let html = format!(
        "<div class=\"marki-flag\" style=\"max-width:{size}px;width:100%;margin:0 auto;\">\
         <img src=\"data:image/svg+xml;base64,{b64}\" \
         style=\"width:100%;height:auto;display:block;\" alt=\"\"></div>",
        size = spec.size,
        b64 = b64,
    );

    Ok(RenderedBlock {
        front_html: html,
        back_html_extras: String::new(),
        assets: Vec::new(),
    })
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// Resolve a `flag` value against the registered sources.
///
/// 1. Split on the first `/` → `(prefix, rest)`.
/// 2. If `prefix` matches a source name → look up `{rest}.svg` in that
///    source (supports subdirectories like `de/by`).
/// 3. Otherwise treat the full value as a path and search every source
///    in order. First match wins.
fn resolve(flag: &str, sources: &[(String, PathBuf)]) -> Result<PathBuf, FlagError> {
    if sources.is_empty() {
        return Err(FlagError::NoSources);
    }

    // Check for source prefix.
    if let Some((prefix, rest)) = flag.split_once('/') {
        if let Some(dir) = source_dir(prefix, sources) {
            return resolve_in_dir(dir, rest).ok_or_else(|| FlagError::NotFound {
                flag: flag.to_string(),
                searched: format!("source \"{prefix}\""),
            });
        }
        // prefix didn't match a source — fall through to search-all
        // with the full flag value (e.g. "de/by" where "de" is a dir,
        // not a source).
    }

    // No prefix match — search all sources.
    for (_name, dir) in sources {
        if let Some(path) = resolve_in_dir(dir, flag) {
            return Ok(path);
        }
    }

    let searched = sources
        .iter()
        .map(|(n, _)| format!("\"{n}\""))
        .collect::<Vec<_>>()
        .join(", ");
    Err(FlagError::NotFound {
        flag: flag.to_string(),
        searched,
    })
}

/// Look up a source directory by name.
fn source_dir<'a>(name: &str, sources: &'a [(String, PathBuf)]) -> Option<&'a Path> {
    sources
        .iter()
        .find(|(n, _)| n == name)
        .map(|(_, d)| d.as_path())
}

/// Try to resolve `path` (without `.svg` extension) inside `dir`.
///
/// Supports subdirectory paths like `de/by` → `dir/de/by.svg`.
/// Falls back to a case-insensitive match on the final filename
/// component when an exact match isn't found.
fn resolve_in_dir(dir: &Path, path: &str) -> Option<PathBuf> {
    // Fast path: exact match.
    let direct = dir.join(format!("{path}.svg"));
    if direct.is_file() {
        return Some(direct);
    }

    // Slow path: case-insensitive on the final component.
    // Split path into parent directories + filename stem.
    let (parent_rel, stem) = match path.rsplit_once('/') {
        Some((p, s)) => (Some(p), s),
        None => (None, path),
    };
    let search_dir = match parent_rel {
        Some(p) => {
            let d = dir.join(p);
            if !d.is_dir() {
                return None;
            }
            d
        }
        None => dir.to_path_buf(),
    };

    let needle = stem.to_ascii_lowercase();
    let entries = std::fs::read_dir(&search_dir).ok()?;
    for entry in entries.flatten() {
        let entry_path = entry.path();
        if entry_path.extension().and_then(|s| s.to_str()) != Some("svg") {
            continue;
        }
        let entry_stem = entry_path.file_stem().and_then(|s| s.to_str())?;
        if entry_stem.to_ascii_lowercase() == needle {
            return Some(entry_path);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn write_svg(dir: &Path, rel_path: &str, body: &str) {
        let path = dir.join(rel_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(&path, body).unwrap();
    }

    fn make_sources(tmp: &Path) -> Vec<(String, PathBuf)> {
        let circle = tmp.join("circle");
        let flags = tmp.join("flags");
        std::fs::create_dir_all(&circle).unwrap();
        std::fs::create_dir_all(&flags).unwrap();

        write_svg(&circle, "de.svg", "<svg>circle-de</svg>");
        write_svg(&circle, "fr.svg", "<svg>circle-fr</svg>");
        write_svg(&flags, "de.svg", "<svg>flags-de</svg>");
        write_svg(&flags, "de/by.svg", "<svg>flags-de-by</svg>");
        write_svg(&flags, "us/ca.svg", "<svg>flags-us-ca</svg>");
        write_svg(&flags, "us/ca/juneau.svg", "<svg>flags-us-ca-juneau</svg>");

        vec![
            ("circle".into(), circle),
            ("flags".into(), flags),
        ]
    }

    #[test]
    fn prefix_routes_to_source() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let p = resolve("circle/de", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));

        let p = resolve("flags/de", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("flags-de"));
    }

    #[test]
    fn prefix_with_subdir() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let p = resolve("flags/de/by", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("flags-de-by"));

        let p = resolve("flags/us/ca/juneau", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("juneau"));
    }

    #[test]
    fn bare_name_searches_all_sources() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        // "de" exists in both — circle is first, so it wins
        let p = resolve("de", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));

        // "fr" only in circle
        let p = resolve("fr", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-fr"));
    }

    #[test]
    fn bare_path_searches_all_sources() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        // "de/by" — "de" is not a source name, search all for de/by.svg
        let p = resolve("de/by", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("flags-de-by"));
    }

    #[test]
    fn case_insensitive_lookup() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let p = resolve("circle/DE", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));
    }

    #[test]
    fn unknown_flag_errors() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let err = resolve("xx", &sources).unwrap_err();
        assert!(matches!(err, FlagError::NotFound { .. }));
    }

    #[test]
    fn unknown_in_named_source_errors() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let err = resolve("circle/xx", &sources).unwrap_err();
        match &err {
            FlagError::NotFound { searched, .. } => assert!(searched.contains("circle")),
            other => panic!("expected NotFound, got {other:?}"),
        }
    }

    #[test]
    fn no_sources_errors() {
        let err = resolve("de", &[]).unwrap_err();
        assert!(matches!(err, FlagError::NoSources));
    }

    #[test]
    fn renders_data_uri_img() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());

        let spec = dsl::FlagSpec { flag: "circle/de".into(), size: 300 };
        let out = render_flag(&sources, &spec).unwrap();
        assert!(out.front_html.contains("max-width:300px"));
        assert!(out.front_html.contains("data:image/svg+xml;base64,"));
        assert!(out.front_html.contains("<img "));
        assert!(out.front_html.contains("margin:0 auto"));
    }

    #[test]
    fn renderer_rejects_bad_toml() {
        let r = FlagRenderer::new(vec![]);
        let mut ctx = RenderCtx {
            source_path: &PathBuf::from("/tmp/x.md"),
            cache_dir: &PathBuf::from("/tmp/cache"),
        };
        let err = r.render("not = [valid", &mut ctx).unwrap_err();
        assert!(matches!(err, BlockError::Parse(_)));
    }

    // -- test helpers --

    struct TempDir(PathBuf);
    impl TempDir {
        fn path(&self) -> &Path { &self.0 }
    }
    impl Drop for TempDir {
        fn drop(&mut self) { let _ = std::fs::remove_dir_all(&self.0); }
    }
    fn tempdir() -> TempDir {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "marki-flag-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&p).unwrap();
        TempDir(p)
    }
}
