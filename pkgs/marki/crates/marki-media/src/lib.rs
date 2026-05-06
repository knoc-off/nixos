//! `marki-media` — render `media` blocks to images or audio.
//!
//! Implements `marki_core::BlockRenderer` for the lang token `media`.
//! See `dsl.rs` for the TOML body format.
//!
//! The renderer supports multiple named media sources. The `src` field
//! in the DSL can optionally prefix a source name to target a specific
//! collection:
//!
//!   - `src = "circle/de"` → look up `de.<ext>` in the "circle" source
//!   - `src = "flags/de/by"` → look up `de/by.<ext>` in the "flags" source
//!   - `src = "de"` → search all sources in order, first match wins
//!
//! Extensions are inferred when missing: the resolver tries a fixed
//! preference list (svg → png → webp → jpg → jpeg → gif → mp3 → ogg
//! → m4a → wav). Authors can also write the extension explicitly
//! (`src = "diagrams/foo.png"`) for exact matches.
//!
//! Resolved files are emitted as `EmittedAsset`s with content-addressed
//! filenames so two cards referencing the same logical file converge in
//! Anki's media collection. The rendered HTML references the asset by
//! basename — no inline base64 — keeping HTML small and letting Anki's
//! native media handling do its thing.

pub mod dsl;
pub mod error;

use std::path::{Path, PathBuf};

use marki_core::{AssetMime, BlockError, BlockRenderer, EmittedAsset, RenderCtx, RenderedBlock};
use marki_core::escape_html as escape_attr;

pub use error::MediaError;

/// Lang token this renderer handles: `media`.
pub const MEDIA_LANG: &str = "media";

/// Image extensions, in resolution preference order.
const IMAGE_EXTS: &[&str] = &["svg", "png", "webp", "jpg", "jpeg", "gif"];

/// Audio extensions, in resolution preference order.
const AUDIO_EXTS: &[&str] = &["mp3", "ogg", "m4a", "wav"];

/// What kind of media a resolved file is. Drives renderer dispatch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaClass {
    Image,
    Audio,
}

/// Media block renderer with multiple named sources.
///
/// Sources are searched in order — the first match wins when no
/// explicit source prefix is given in the DSL.
pub struct MediaRenderer {
    /// Named sources in priority order: `(name, directory)`.
    sources: Vec<(String, PathBuf)>,
}

impl MediaRenderer {
    pub fn new(sources: Vec<(String, PathBuf)>) -> Self {
        Self { sources }
    }
}

impl BlockRenderer for MediaRenderer {
    fn lang(&self) -> &'static str {
        MEDIA_LANG
    }

    fn render(&self, src: &str, _ctx: &mut RenderCtx<'_>) -> Result<RenderedBlock, BlockError> {
        let spec = dsl::parse_media_spec(src).map_err(|e| BlockError::Parse(e.to_string()))?;
        Ok(render_media(&self.sources, &spec)?)
    }
}

fn render_media(
    sources: &[(String, PathBuf)],
    spec: &dsl::MediaSpec,
) -> Result<RenderedBlock, MediaError> {
    let (path, ext) = resolve(&spec.src, sources)?;
    let class = classify(ext).ok_or_else(|| MediaError::UnsupportedExt {
        src: spec.src.clone(),
        ext: ext.to_string(),
    })?;
    let bytes = std::fs::read(&path)?;

    let basename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("media");
    let asset_filename = content_addressed_filename(&bytes, basename);
    let mime = mime_for(ext);

    let html = match class {
        MediaClass::Image => render_image_html(spec, &asset_filename),
        MediaClass::Audio => render_audio_html(spec, &asset_filename),
    };

    Ok(RenderedBlock {
        front_html: html,
        back_html_extras: String::new(),
        assets: vec![EmittedAsset {
            filename: asset_filename,
            bytes,
            mime,
        }],
    })
}

// ---------------------------------------------------------------------------
// HTML rendering
// ---------------------------------------------------------------------------

fn render_image_html(spec: &dsl::MediaSpec, asset_filename: &str) -> String {
    let size = spec.size.unwrap_or(dsl::DEFAULT_IMAGE_SIZE);
    let alt = escape_attr(spec.alt.as_deref().unwrap_or(""));
    format!(
        "<div class=\"marki-media marki-image\" \
         style=\"max-width:{size}px;width:100%;margin:0 auto;\">\
         <img src=\"{src}\" alt=\"{alt}\" \
         style=\"width:100%;height:auto;display:block;\"></div>",
        size = size,
        src = escape_attr(asset_filename),
        alt = alt,
    )
}

fn render_audio_html(spec: &dsl::MediaSpec, asset_filename: &str) -> String {
    let mut attrs = String::new();
    if spec.controls {
        attrs.push_str(" controls");
    }
    if spec.r#loop {
        attrs.push_str(" loop");
    }
    if spec.autoplay {
        attrs.push_str(" autoplay");
    }
    attrs.push_str(&format!(" preload=\"{}\"", spec.preload.as_str()));
    if let Some(alt) = spec.alt.as_deref().filter(|s| !s.is_empty()) {
        attrs.push_str(&format!(" aria-label=\"{}\"", escape_attr(alt)));
    }
    format!(
        "<div class=\"marki-media marki-audio\">\
         <audio src=\"{src}\"{attrs} \
         style=\"width:100%;display:block;\"></audio></div>",
        src = escape_attr(asset_filename),
        attrs = attrs,
    )
}

// ---------------------------------------------------------------------------
// Asset filename
// ---------------------------------------------------------------------------

/// Build a content-addressed filename of the form
/// `marki-media-<8 hex>-<orig basename>`. The prefix prevents collisions
/// with markdown-inline media (which uses a separate scheme in
/// `markid::sync::media`).
fn content_addressed_filename(bytes: &[u8], orig_basename: &str) -> String {
    let hex = blake3::hash(bytes).to_hex();
    let short = &hex.as_str()[..8];
    format!("marki-media-{short}-{orig_basename}")
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/// Map a file extension to a media class. Returns `None` for unknown
/// extensions.
pub fn classify(ext: &str) -> Option<MediaClass> {
    let ext = ext.to_ascii_lowercase();
    if IMAGE_EXTS.iter().any(|e| *e == ext) {
        Some(MediaClass::Image)
    } else if AUDIO_EXTS.iter().any(|e| *e == ext) {
        Some(MediaClass::Audio)
    } else {
        None
    }
}

fn mime_for(ext: &str) -> AssetMime {
    match ext.to_ascii_lowercase().as_str() {
        "svg" => AssetMime::SvgXml,
        "png" => AssetMime::ImagePng,
        "jpg" | "jpeg" => AssetMime::ImageJpeg,
        "webp" => AssetMime::ImageWebp,
        "gif" => AssetMime::ImageGif,
        "mp3" => AssetMime::AudioMpeg,
        "ogg" => AssetMime::AudioOgg,
        "m4a" => AssetMime::AudioMp4,
        "wav" => AssetMime::AudioWav,
        // classify() is checked first, so this branch is unreachable in
        // practice. Pick the most generic image bucket as a safe stub.
        _ => AssetMime::ImagePng,
    }
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/// Resolve a `src` value against the registered sources.
///
/// Returns `(absolute path, extension without dot)`.
///
/// 1. Split on the first `/` → `(prefix, rest)`.
/// 2. If `prefix` matches a source name → look up `rest` in that source.
/// 3. Otherwise treat the full value as a path and search every source
///    in order. First match wins.
///
/// `rest` (or the bare value) may be a leaf with or without an
/// extension — see [`resolve_in_dir`].
fn resolve(src: &str, sources: &[(String, PathBuf)]) -> Result<(PathBuf, &'static str), MediaError> {
    if sources.is_empty() {
        return Err(MediaError::NoSources);
    }

    if let Some((prefix, rest)) = src.split_once('/') {
        if let Some(dir) = source_dir(prefix, sources) {
            return resolve_in_dir(dir, rest).ok_or_else(|| MediaError::NotFound {
                src: src.to_string(),
                searched: format!("source \"{prefix}\""),
            });
        }
    }

    for (_name, dir) in sources {
        if let Some(found) = resolve_in_dir(dir, src) {
            return Ok(found);
        }
    }

    let searched = sources
        .iter()
        .map(|(n, _)| format!("\"{n}\""))
        .collect::<Vec<_>>()
        .join(", ");
    Err(MediaError::NotFound {
        src: src.to_string(),
        searched,
    })
}

fn source_dir<'a>(name: &str, sources: &'a [(String, PathBuf)]) -> Option<&'a Path> {
    sources
        .iter()
        .find(|(n, _)| n == name)
        .map(|(_, d)| d.as_path())
}

/// Try to resolve `path` inside `dir`. Returns the resolved file path
/// and the matching extension (without dot).
///
/// If `path` ends with a known extension (image or audio), only that
/// exact extension is tried (with case-insensitive fallback on the
/// final filename component, matching the directory traversal at all
/// levels). Otherwise the resolver tries each known extension in the
/// fixed preference order — `IMAGE_EXTS` first, then `AUDIO_EXTS`.
fn resolve_in_dir(dir: &Path, path: &str) -> Option<(PathBuf, &'static str)> {
    // Explicit-extension fast path.
    if let Some((stem, ext)) = split_known_ext(path) {
        if let Some(p) = lookup_with_ext(dir, stem, ext) {
            return Some((p, ext));
        }
        // Author asked for a specific extension; don't fall back to
        // searching others — that would silently mask typos.
        return None;
    }

    // No extension — try each in preference order.
    for ext in IMAGE_EXTS.iter().chain(AUDIO_EXTS.iter()) {
        if let Some(p) = lookup_with_ext(dir, path, ext) {
            return Some((p, *ext));
        }
    }
    None
}

/// Returns `Some((stem, ext))` if `path`'s last component has a known
/// (image or audio) extension. Otherwise `None`.
fn split_known_ext(path: &str) -> Option<(&str, &'static str)> {
    let dot = path.rfind('.')?;
    // Reject `.foo` segments inside parent directories (no slash after
    // the dot but a slash before it could mean "directory.with.dot").
    // The rfind ensures we look at the last dot in the whole path —
    // good enough.
    let ext_lower = path[dot + 1..].to_ascii_lowercase();
    for known in IMAGE_EXTS.iter().chain(AUDIO_EXTS.iter()) {
        if ext_lower == *known {
            return Some((&path[..dot], *known));
        }
    }
    None
}

/// Look up `{stem}.{ext}` inside `dir`, with a case-insensitive
/// fallback on the leaf filename if the exact form isn't present.
/// Supports subdirectory paths in `stem` (e.g. `de/by`).
fn lookup_with_ext(dir: &Path, stem: &str, ext: &str) -> Option<PathBuf> {
    // Fast path: exact match.
    let direct = dir.join(format!("{stem}.{ext}"));
    if direct.is_file() {
        return Some(direct);
    }

    // Slow path: case-insensitive on the final component.
    let (parent_rel, leaf) = match stem.rsplit_once('/') {
        Some((p, s)) => (Some(p), s),
        None => (None, stem),
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

    let needle_stem = leaf.to_ascii_lowercase();
    let needle_ext = ext.to_ascii_lowercase();
    let entries = std::fs::read_dir(&search_dir).ok()?;
    for entry in entries.flatten() {
        let entry_path = entry.path();
        let entry_ext = entry_path
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.to_ascii_lowercase());
        if entry_ext.as_deref() != Some(needle_ext.as_str()) {
            continue;
        }
        let entry_stem = entry_path.file_stem().and_then(|s| s.to_str())?;
        if entry_stem.to_ascii_lowercase() == needle_stem {
            return Some(entry_path);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn write_file(dir: &Path, rel_path: &str, body: &[u8]) {
        let path = dir.join(rel_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).unwrap();
        }
        std::fs::write(&path, body).unwrap();
    }

    fn make_sources(tmp: &Path) -> Vec<(String, PathBuf)> {
        let circle = tmp.join("circle");
        let flags = tmp.join("flags");
        let audio = tmp.join("audio");
        std::fs::create_dir_all(&circle).unwrap();
        std::fs::create_dir_all(&flags).unwrap();
        std::fs::create_dir_all(&audio).unwrap();

        write_file(&circle, "de.svg", b"<svg>circle-de</svg>");
        write_file(&circle, "fr.svg", b"<svg>circle-fr</svg>");
        write_file(&flags, "de.svg", b"<svg>flags-de</svg>");
        write_file(&flags, "de/by.svg", b"<svg>flags-de-by</svg>");
        write_file(&flags, "us/ca.svg", b"<svg>flags-us-ca</svg>");
        write_file(&audio, "morning.mp3", b"ID3-fake-mp3");
        write_file(&audio, "evening.ogg", b"OggS-fake-ogg");

        vec![
            ("circle".into(), circle),
            ("flags".into(), flags),
            ("audio".into(), audio),
        ]
    }

    // -- Resolution --------------------------------------------------

    #[test]
    fn prefix_routes_to_source() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let (p, ext) = resolve("circle/de", &sources).unwrap();
        assert_eq!(ext, "svg");
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));
    }

    #[test]
    fn prefix_with_subdir() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let (p, _) = resolve("flags/de/by", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("flags-de-by"));
    }

    #[test]
    fn bare_name_searches_all_sources() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        // "de" exists in both circle and flags; circle is first.
        let (p, _) = resolve("de", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));
    }

    #[test]
    fn case_insensitive_lookup() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let (p, _) = resolve("circle/DE", &sources).unwrap();
        assert!(std::fs::read_to_string(&p).unwrap().contains("circle-de"));
    }

    #[test]
    fn unknown_src_errors() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let err = resolve("xx", &sources).unwrap_err();
        assert!(matches!(err, MediaError::NotFound { .. }));
    }

    #[test]
    fn no_sources_errors() {
        let err = resolve("de", &[]).unwrap_err();
        assert!(matches!(err, MediaError::NoSources));
    }

    #[test]
    fn finds_audio_without_extension() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let (p, ext) = resolve("audio/morning", &sources).unwrap();
        assert_eq!(ext, "mp3");
        assert!(p.to_string_lossy().ends_with("morning.mp3"));
    }

    #[test]
    fn extension_preference_picks_svg_over_png() {
        // Both circle/de.svg (already there) and circle/de.png exist.
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        write_file(&sources[0].1, "de.png", &[0x89, b'P', b'N', b'G']);
        let (_, ext) = resolve("circle/de", &sources).unwrap();
        assert_eq!(ext, "svg");
    }

    #[test]
    fn extension_preference_falls_through_to_png_when_no_svg() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        write_file(&sources[0].1, "logo.png", &[0x89, b'P', b'N', b'G']);
        let (_, ext) = resolve("circle/logo", &sources).unwrap();
        assert_eq!(ext, "png");
    }

    #[test]
    fn explicit_extension_forces_match() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        write_file(&sources[0].1, "logo.svg", b"<svg>");
        write_file(&sources[0].1, "logo.png", &[0x89, b'P', b'N', b'G']);
        // Without explicit ext, svg wins.
        let (_, e_default) = resolve("circle/logo", &sources).unwrap();
        assert_eq!(e_default, "svg");
        // With explicit `.png`, png wins.
        let (p, e_explicit) = resolve("circle/logo.png", &sources).unwrap();
        assert_eq!(e_explicit, "png");
        assert!(p.to_string_lossy().ends_with("logo.png"));
    }

    #[test]
    fn explicit_extension_no_fallback_on_typo() {
        // `circle/de.png` doesn't exist but `circle/de.svg` does. With
        // an explicit extension we should NOT silently fall back.
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let err = resolve("circle/de.png", &sources).unwrap_err();
        assert!(matches!(err, MediaError::NotFound { .. }));
    }

    // -- Classification ----------------------------------------------

    #[test]
    fn classify_image_extensions() {
        for ext in IMAGE_EXTS {
            assert_eq!(classify(ext), Some(MediaClass::Image), "{ext}");
        }
    }

    #[test]
    fn classify_audio_extensions() {
        for ext in AUDIO_EXTS {
            assert_eq!(classify(ext), Some(MediaClass::Audio), "{ext}");
        }
    }

    #[test]
    fn classify_unknown_returns_none() {
        assert_eq!(classify("txt"), None);
        assert_eq!(classify("pdf"), None);
    }

    #[test]
    fn classify_is_case_insensitive() {
        assert_eq!(classify("SVG"), Some(MediaClass::Image));
        assert_eq!(classify("Mp3"), Some(MediaClass::Audio));
    }

    // -- Rendering ----------------------------------------------------

    #[test]
    fn renders_image_with_basename_ref() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "circle/de".into(),
            size: Some(300),
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(out.front_html.contains("max-width:300px"));
        assert!(out.front_html.contains("<img "));
        assert!(out.front_html.contains("marki-media-"));
        assert!(out.front_html.contains("-de.svg"));
        assert!(!out.front_html.contains("data:image"));
        assert_eq!(out.assets.len(), 1);
        assert_eq!(out.assets[0].mime, AssetMime::SvgXml);
    }

    #[test]
    fn image_default_size_is_200() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "circle/de".into(),
            size: None,
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(out.front_html.contains("max-width:200px"));
    }

    #[test]
    fn image_alt_defaults_to_empty() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "circle/de".into(),
            size: None,
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(out.front_html.contains("alt=\"\""));
    }

    #[test]
    fn image_alt_is_escaped() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "circle/de".into(),
            size: None,
            alt: Some(r#"a "quoted" <flag>"#.to_string()),
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(out.front_html.contains("&quot;quoted&quot;"));
        assert!(out.front_html.contains("&lt;flag&gt;"));
    }

    #[test]
    fn renders_audio_with_default_attrs() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "audio/morning".into(),
            size: None,
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(out.front_html.contains("<audio "));
        assert!(out.front_html.contains(" controls"));
        assert!(out.front_html.contains("preload=\"auto\""));
        assert!(!out.front_html.contains(" loop"));
        assert!(!out.front_html.contains(" autoplay"));
        assert!(out.front_html.contains("morning.mp3"));
        assert_eq!(out.assets[0].mime, AssetMime::AudioMpeg);
    }

    #[test]
    fn audio_respects_overrides() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "audio/morning".into(),
            size: Some(300), // ignored for audio
            alt: Some("morning".into()),
            controls: false,
            r#loop: true,
            autoplay: true,
            preload: dsl::PreloadMode::None,
        };
        let out = render_media(&sources, &spec).unwrap();
        assert!(!out.front_html.contains(" controls"));
        assert!(out.front_html.contains(" loop"));
        assert!(out.front_html.contains(" autoplay"));
        assert!(out.front_html.contains("preload=\"none\""));
        assert!(out.front_html.contains("aria-label=\"morning\""));
        // size silently ignored — no max-width on audio container.
        assert!(!out.front_html.contains("max-width:300px"));
    }

    #[test]
    fn emitted_asset_is_content_addressed() {
        let tmp = tempdir();
        let sources = make_sources(tmp.path());
        let spec = dsl::MediaSpec {
            src: "circle/de".into(),
            size: None,
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        let a = render_media(&sources, &spec).unwrap();
        let b = render_media(&sources, &spec).unwrap();
        assert_eq!(a.assets[0].filename, b.assets[0].filename);
        assert!(a.assets[0].filename.starts_with("marki-media-"));
    }

    #[test]
    fn unsupported_extension_errors() {
        let tmp = tempdir();
        let mut sources = make_sources(tmp.path());
        // Add a source containing only an unsupported extension.
        let docs = tmp.path().join("docs");
        std::fs::create_dir_all(&docs).unwrap();
        write_file(&docs, "spec.txt", b"hello");
        sources.push(("docs".into(), docs));
        let spec = dsl::MediaSpec {
            src: "docs/spec.txt".into(),
            size: None,
            alt: None,
            controls: true,
            r#loop: false,
            autoplay: false,
            preload: dsl::PreloadMode::Auto,
        };
        // resolve() doesn't recognise .txt as a known extension, so it
        // falls through to the bare-name search, which won't find any
        // matching extension either → NotFound.
        let err = render_media(&sources, &spec).unwrap_err();
        assert!(matches!(err, MediaError::NotFound { .. }));
    }

    #[test]
    fn renderer_rejects_bad_toml() {
        let r = MediaRenderer::new(vec![]);
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
        fn path(&self) -> &Path {
            &self.0
        }
    }
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    fn tempdir() -> TempDir {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "marki-media-test-{}-{}",
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
