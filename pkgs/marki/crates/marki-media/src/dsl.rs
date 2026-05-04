//! TOML body of a `media` fenced block.
//!
//! Authors write things like:
//!
//! ```toml
//! src = "circle/de"           # image — resolves to circle/de.svg
//! src = "audio/morning"       # audio — resolves to audio/morning.mp3
//! src = "diagrams/foo.png"    # explicit extension forces exact match
//! size = 200                  # optional; max-width in CSS px (images only)
//! alt = "German flag"         # optional; defaults to ""
//!
//! # Audio-only knobs (silently ignored on images):
//! controls = true             # default true
//! loop = false                # default false
//! autoplay = false            # default false
//! preload = "auto"            # "none" | "metadata" | "auto"; default "auto"
//! ```
//!
//! The `src` field is a path with an optional source prefix. If the
//! first component matches a registered source name, the rest is looked
//! up in that source's directory. Otherwise all sources are searched in
//! registration order and the first match wins. If `src` has no
//! extension, the resolver tries a fixed preference list of image and
//! audio extensions (svg → png → webp → jpg → jpeg → gif → mp3 → ogg
//! → m4a → wav). Type is inferred from the extension that wins.

use serde::{Deserialize, Serialize};

/// Top-level media block.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MediaSpec {
    /// Media reference — optionally prefixed with a source name.
    /// Extension is optional: if omitted, the resolver searches a
    /// fixed preference list of image then audio extensions.
    pub src: String,

    /// Max-width in CSS pixels for image renders. Defaults to 200.
    /// Silently ignored when `src` resolves to audio.
    #[serde(default)]
    pub size: Option<u32>,

    /// Alt text / aria-label. Defaults to empty string.
    #[serde(default)]
    pub alt: Option<String>,

    /// Audio: show built-in <audio> controls. Default true.
    #[serde(default = "default_true")]
    pub controls: bool,

    /// Audio: loop on completion. Default false.
    #[serde(default, rename = "loop")]
    pub r#loop: bool,

    /// Audio: autoplay on card load. Default false.
    #[serde(default)]
    pub autoplay: bool,

    /// Audio: preload mode. Default `auto` — Anki stores media locally,
    /// so there's no fetch cost.
    #[serde(default = "default_preload_auto")]
    pub preload: PreloadMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum PreloadMode {
    None,
    Metadata,
    Auto,
}

impl PreloadMode {
    pub fn as_str(self) -> &'static str {
        match self {
            PreloadMode::None => "none",
            PreloadMode::Metadata => "metadata",
            PreloadMode::Auto => "auto",
        }
    }
}

fn default_true() -> bool {
    true
}

fn default_preload_auto() -> PreloadMode {
    PreloadMode::Auto
}

/// Default max-width for image renders.
pub const DEFAULT_IMAGE_SIZE: u32 = 200;

pub fn parse_media_spec(src: &str) -> Result<MediaSpec, toml::de::Error> {
    toml::from_str(src)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_image() {
        let spec = parse_media_spec(r#"src = "circle/de""#).unwrap();
        assert_eq!(spec.src, "circle/de");
        assert_eq!(spec.size, None);
        assert_eq!(spec.alt, None);
        // Audio defaults still parse on image specs (silently ignored at render time).
        assert!(spec.controls);
        assert!(!spec.r#loop);
        assert!(!spec.autoplay);
        assert_eq!(spec.preload, PreloadMode::Auto);
    }

    #[test]
    fn parses_with_size_and_alt() {
        let spec = parse_media_spec(
            r#"
src = "de"
size = 400
alt = "German flag"
"#,
        )
        .unwrap();
        assert_eq!(spec.size, Some(400));
        assert_eq!(spec.alt.as_deref(), Some("German flag"));
    }

    #[test]
    fn parses_audio_overrides() {
        let spec = parse_media_spec(
            r#"
src = "audio/foo"
controls = false
loop = true
autoplay = true
preload = "metadata"
"#,
        )
        .unwrap();
        assert!(!spec.controls);
        assert!(spec.r#loop);
        assert!(spec.autoplay);
        assert_eq!(spec.preload, PreloadMode::Metadata);
    }

    #[test]
    fn rejects_unknown_fields() {
        let err = parse_media_spec("src = \"de\"\nbogus = true").unwrap_err();
        assert!(err.to_string().contains("bogus"));
    }

    #[test]
    fn requires_src_field() {
        let err = parse_media_spec("size = 200").unwrap_err();
        assert!(err.to_string().contains("src"));
    }

    #[test]
    fn rejects_old_flag_field() {
        // Authors used to write `flag = "..."`. After the rename to
        // `media`, that field no longer exists — `deny_unknown_fields`
        // catches it.
        let err = parse_media_spec(r#"flag = "de""#).unwrap_err();
        assert!(err.to_string().contains("flag") || err.to_string().contains("src"));
    }

    #[test]
    fn rejects_old_country_field() {
        let err = parse_media_spec(r#"country = "de""#).unwrap_err();
        assert!(err.to_string().contains("country") || err.to_string().contains("src"));
    }

    #[test]
    fn preload_variants_parse() {
        for (s, want) in [
            ("none", PreloadMode::None),
            ("metadata", PreloadMode::Metadata),
            ("auto", PreloadMode::Auto),
        ] {
            let spec = parse_media_spec(&format!("src = \"x\"\npreload = \"{s}\"")).unwrap();
            assert_eq!(spec.preload, want);
        }
    }
}
