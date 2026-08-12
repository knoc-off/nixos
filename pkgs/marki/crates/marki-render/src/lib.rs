//! The block-renderer plugin surface.
//!
//! A *renderer* turns one authored block into a [`Fragment`] of HTML plus any
//! media files it needed to produce. Renderers live in their own crates
//! (`marki-map`, `marki-media`, `marki-typst`); this crate holds only the
//! contract between them and the daemon, so neither side needs to depend on
//! the other.
//!
//! A block reaches a renderer by one of two routes, which is what [`Input`]
//! distinguishes:
//!
//!   * a fenced code block in the markdown, whose body is handed over
//!     verbatim as [`Input::Raw`];
//!   * a script-side constructor such as Lua's `map{...}`, whose table is
//!     handed over already structured as [`Input::Spec`].
//!
//! Both routes converge via [`Input::deserialize`], so a renderer implements
//! its logic once and gets the script-side constructor for free.
//!
//! No I/O happens in this crate.

use std::path::Path;

mod escape;

pub use escape::escape_html;

/// One block handed to a renderer.
///
/// The two variants exist so a script-side constructor does not have to
/// serialise its table to TOML text just for the renderer to parse it back.
#[derive(Debug, Clone)]
pub enum Input<'a> {
    /// Verbatim fenced-block body, in the renderer's own DSL.
    Raw(&'a str),
    /// Structured value produced by a script-side constructor.
    Spec(toml::Value),
}

impl Input<'_> {
    /// Deserialize into the renderer's own spec type, from either route.
    ///
    /// This is the normal way to consume an `Input`: renderers whose block
    /// body is TOML get both routes handled in one call.
    pub fn deserialize<T: serde::de::DeserializeOwned>(self) -> Result<T, RenderError> {
        match self {
            Input::Raw(src) => toml::from_str(src).map_err(|e| RenderError::Parse(e.to_string())),
            Input::Spec(v) => v.try_into().map_err(|e: toml::de::Error| {
                RenderError::Parse(e.to_string())
            }),
        }
    }

    /// View as a TOML table, for renderers that merge the block against
    /// configured defaults before deserializing.
    pub fn into_table(self) -> Result<toml::Table, RenderError> {
        match self {
            Input::Raw(src) => toml::from_str(src).map_err(|e| RenderError::Parse(e.to_string())),
            Input::Spec(toml::Value::Table(t)) => Ok(t),
            Input::Spec(v) => Err(RenderError::Parse(format!(
                "expected a table, got {}",
                v.type_str()
            ))),
        }
    }

    /// Borrow the body as text, for renderers whose block body is source
    /// code rather than a DSL (e.g. Typst).
    ///
    /// The `Spec` route supplies it as a lone `source` key.
    pub fn as_source(&self) -> Result<&str, RenderError> {
        match self {
            Input::Raw(src) => Ok(src),
            Input::Spec(toml::Value::Table(t)) => match t.get("source") {
                Some(toml::Value::String(s)) => Ok(s),
                Some(v) => Err(RenderError::Parse(format!(
                    "`source` must be a string, got {}",
                    v.type_str()
                ))),
                None => Err(RenderError::Parse("missing `source`".into())),
            },
            Input::Spec(v) => Err(RenderError::Parse(format!(
                "expected a table, got {}",
                v.type_str()
            ))),
        }
    }
}

/// What a renderer hands back.
#[derive(Debug, Clone, Default)]
pub struct Fragment {
    /// HTML for the side the block was authored on.
    pub html: String,
    /// HTML appended to the back side, shown once the card is flipped.
    /// Used for `<style>` blocks that override front-side CSS to implement
    /// reveal-on-flip.
    pub reveal: String,
    /// Files the renderer produced, for the media collection.
    pub assets: Vec<Asset>,
}

/// One file emitted by a renderer, stored in the media collection verbatim
/// under `filename`.
#[derive(Debug, Clone)]
pub struct Asset {
    /// Final media basename. Renderers produce content-addressed names so
    /// two cards referencing the same logical asset converge on one file.
    pub filename: String,
    /// Raw bytes, held in memory.
    pub bytes: Vec<u8>,
    /// MIME hint, primarily for diagnostics -- Anki infers the content type
    /// from the filename extension.
    pub mime: AssetMime,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AssetMime {
    SvgXml,
    ImagePng,
    ImageJpeg,
    ImageWebp,
    ImageGif,
    AudioMpeg,
    AudioOgg,
    AudioMp4,
    AudioWav,
    ApplicationJson,
}

impl AssetMime {
    pub fn as_str(self) -> &'static str {
        match self {
            AssetMime::SvgXml => "image/svg+xml",
            AssetMime::ImagePng => "image/png",
            AssetMime::ImageJpeg => "image/jpeg",
            AssetMime::ImageWebp => "image/webp",
            AssetMime::ImageGif => "image/gif",
            AssetMime::AudioMpeg => "audio/mpeg",
            AssetMime::AudioOgg => "audio/ogg",
            AssetMime::AudioMp4 => "audio/mp4",
            AssetMime::AudioWav => "audio/wav",
            AssetMime::ApplicationJson => "application/json",
        }
    }
}

/// Context passed to a renderer at render time. Kept minimal on purpose --
/// anything that needs to grow goes here, not into the trait signature.
pub struct RenderCtx<'a> {
    /// Path of the markdown file the block came from. Renderers use this for
    /// diagnostics and for resolving defaults by path. May be synthetic in
    /// tests.
    pub source_path: &'a Path,
    /// Cache root the renderer may write into.
    pub cache_dir: &'a Path,
}

/// Errors a renderer can return. The daemon turns each into a per-card
/// failure: logged, recorded in the cycle outcome, batch continues.
#[derive(Debug, thiserror::Error)]
pub enum RenderError {
    /// Bad DSL or bad block body.
    #[error("parse: {0}")]
    Parse(String),
    /// Reference to data that does not exist (unknown OSM relation, etc).
    #[error("resolve: {0}")]
    Resolve(String),
    /// Network failure or rate limit.
    #[error("network: {0}")]
    Network(String),
    /// Cache I/O problem.
    #[error("cache: {0}")]
    Cache(String),
    /// Other I/O problem.
    #[error("io: {0}")]
    Io(String),
    /// Catch-all for renderer-internal errors.
    #[error("render: {0}")]
    Internal(String),
}

/// Implemented by block renderers. The daemon owns a registry keyed by
/// [`Self::lang`].
pub trait Renderer: Send + Sync {
    /// Block token this renderer handles (e.g. `"map"`). This is both the
    /// fenced-code lang and the script-side constructor name.
    fn lang(&self) -> &'static str;

    /// Render one block.
    fn render(&self, input: Input<'_>, ctx: &mut RenderCtx<'_>) -> Result<Fragment, RenderError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, PartialEq, Deserialize)]
    struct Spec {
        src: String,
        #[serde(default)]
        width: u32,
    }

    #[test]
    fn both_routes_deserialize_alike() {
        let raw = Input::Raw("src = \"a.png\"\nwidth = 3\n")
            .deserialize::<Spec>()
            .unwrap();

        let mut t = toml::Table::new();
        t.insert("src".into(), toml::Value::String("a.png".into()));
        t.insert("width".into(), toml::Value::Integer(3));
        let spec = Input::Spec(toml::Value::Table(t))
            .deserialize::<Spec>()
            .unwrap();

        assert_eq!(raw, spec);
    }

    #[test]
    fn malformed_raw_is_a_parse_error() {
        let e = Input::Raw("src = ").deserialize::<Spec>().unwrap_err();
        assert!(matches!(e, RenderError::Parse(_)));
    }

    #[test]
    fn spec_route_reports_missing_field() {
        let e = Input::Spec(toml::Value::Table(toml::Table::new()))
            .deserialize::<Spec>()
            .unwrap_err();
        assert!(matches!(e, RenderError::Parse(_)));
    }

    #[test]
    fn non_table_spec_rejected_by_into_table() {
        let e = Input::Spec(toml::Value::Integer(1)).into_table().unwrap_err();
        assert!(matches!(e, RenderError::Parse(_)));
    }

    #[test]
    fn source_from_either_route() {
        assert_eq!(Input::Raw("#set page()").as_source().unwrap(), "#set page()");

        let mut t = toml::Table::new();
        t.insert("source".into(), toml::Value::String("#set page()".into()));
        assert_eq!(
            Input::Spec(toml::Value::Table(t)).as_source().unwrap(),
            "#set page()"
        );
    }

    #[test]
    fn source_missing_is_an_error() {
        let e = Input::Spec(toml::Value::Table(toml::Table::new()))
            .as_source()
            .unwrap_err();
        assert!(matches!(e, RenderError::Parse(_)));
    }
}
