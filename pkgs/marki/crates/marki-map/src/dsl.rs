//! TOML body of a `map` fenced block.
//!
//! Authors write things like:
//!
//! ```toml
//! size = [600, 400]
//! style = "atlas"           # optional theme name; defaults to "atlas"
//!
//! [layers.base]
//! features = ["coastline", "country/DEU"]
//! context = ["neighbors/DEU"]
//!
//! [layers.answer]
//! highlights = ["admin1/DEU/Bavaria"]
//! reveal = "fade"           # optional; non-base layers default to fade
//! ```
//!
//! Fields and shapes are deliberately minimal — the renderer rejects
//! anything it doesn't understand so authors get fast feedback.

use serde::{Deserialize, Serialize};
use indexmap::IndexMap;

/// Top-level map block.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct MapSpec {
    /// `[width, height]` in CSS pixels. Treated as a maximum budget —
    /// the renderer may shrink one dimension to match the projected
    /// aspect. Defaults to `[600, 400]`.
    #[serde(default = "default_size")]
    pub size: [u32; 2],

    /// Optional theme name; defaults to the bundled `atlas` theme.
    #[serde(default = "default_style")]
    pub style: String,

    /// Layers, keyed by name. `IndexMap` preserves TOML source order,
    /// which controls DOM stacking: earlier layers render underneath
    /// later ones. Authors should write `base` first.
    pub layers: IndexMap<String, LayerSpec>,
}

fn default_style() -> String {
    "atlas".to_string()
}

fn default_size() -> [u32; 2] {
    [600, 400]
}

/// One named layer inside a map block.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct LayerSpec {
    /// Geometry references to draw on this layer. Each entry is a
    /// short string like `coastline`, `country/DEU`,
    /// `admin1/DEU/Bavaria`, or `relation/2145268`.
    /// These features **define the viewport** (bounding box) as well
    /// as being drawn.
    #[serde(default)]
    pub features: Vec<String>,

    /// Geometry references drawn for visual context but that do NOT
    /// affect the viewport bounding box. Use this for neighbours,
    /// coastlines, or any background geometry that should be visible
    /// but shouldn't expand the camera.
    #[serde(default)]
    pub context: Vec<String>,

    /// Feature references drawn with the theme's `highlight` role.
    #[serde(default)]
    pub highlights: Vec<String>,

    /// Reveal mode for this layer. Defaults to [`RevealMode::None`] for
    /// the conventional `base` layer name and [`RevealMode::Fade`] for
    /// every other layer name (handled at apply time, not in the
    /// `Default` impl, so the DSL can stay terse).
    #[serde(default)]
    pub reveal: Option<RevealMode>,

    /// Optional per-layer overrides for the highlight role's styling.
    /// Unset fields inherit from the active theme.
    #[serde(default)]
    pub style: Option<HighlightStyle>,
}

/// Per-layer overrides for highlight styling. Any field left `None`
/// inherits from the active theme's `highlight` role.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HighlightStyle {
    pub fill: Option<String>,
    pub stroke: Option<String>,
    pub stroke_width: Option<f64>,
}

/// How a layer transitions between front and back of a card.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RevealMode {
    /// Always visible.
    None,
    /// Hidden on the front; faded in on the back.
    Fade,
}

impl LayerSpec {
    /// Resolve the effective reveal mode for a layer named `name`.
    ///
    /// * If the author set `reveal:` explicitly, use that.
    /// * Otherwise: `base` → `None` (always shown); anything else →
    ///   `Fade` (hidden on front, faded in on back).
    pub fn effective_reveal(&self, name: &str) -> RevealMode {
        match self.reveal {
            Some(m) => m,
            None if name == "base" => RevealMode::None,
            None => RevealMode::Fade,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum DslError {
    #[error("toml: {0}")]
    Toml(#[from] toml::de::Error),
    #[error("layers must not be empty")]
    NoLayers,
    #[error("size dimensions must be positive (got {0}x{1})")]
    BadSize(u32, u32),
}

/// Parse a `map` block body as TOML and validate it.
pub fn parse_map_spec(src: &str) -> Result<MapSpec, DslError> {
    let spec: MapSpec = toml::from_str(src)?;
    if spec.layers.is_empty() {
        return Err(DslError::NoLayers);
    }
    if spec.size[0] == 0 || spec.size[1] == 0 {
        return Err(DslError::BadSize(spec.size[0], spec.size[1]));
    }
    Ok(spec)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn minimal_spec_parses() {
        let src = r#"
size = [600, 400]

[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(s.size, [600, 400]);
        assert_eq!(s.style, "atlas");
        assert_eq!(s.layers["base"].features, vec!["coastline".to_string()]);
    }

    #[test]
    fn highlight_only_layer_parses() {
        let src = r#"
size = [400, 300]

[layers.base]
features = ["country/DEU"]

[layers.answer]
highlights = ["admin1/DEU/Bavaria"]
"#;
        let s = parse_map_spec(src).unwrap();
        let answer = &s.layers["answer"];
        assert_eq!(answer.highlights, vec!["admin1/DEU/Bavaria"]);
        assert!(answer.features.is_empty());
    }

    #[test]
    fn unknown_field_rejected() {
        let src = r#"
size = [600, 400]
bogus = true

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::Toml(_)), "got: {err:?}");
    }

    #[test]
    fn no_layers_is_error() {
        let src = r#"
size = [600, 400]

[layers]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::NoLayers));
    }

    #[test]
    fn zero_size_is_error() {
        let src = r#"
size = [0, 400]

[layers.base]
features = []
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::BadSize(0, 400)));
    }

    #[test]
    fn reveal_defaults_by_layer_name() {
        let src = r#"
size = [600, 400]

[layers.base]
features = ["coastline"]

[layers.answer]
features = ["country/DEU"]

[layers.notes]
features = []
reveal = "none"
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(
            s.layers["base"].effective_reveal("base"),
            RevealMode::None
        );
        assert_eq!(
            s.layers["answer"].effective_reveal("answer"),
            RevealMode::Fade
        );
        // Explicit reveal=none on a non-base layer wins.
        assert_eq!(
            s.layers["notes"].effective_reveal("notes"),
            RevealMode::None
        );
    }

    #[test]
    fn size_defaults_to_600x400() {
        let src = r#"
[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(s.size, [600, 400]);
    }

    #[test]
    fn multiple_highlights_in_one_layer() {
        let src = r#"
[layers.base]
features = ["country/ITA"]
[layers.answer]
highlights = ["region/ITA/Piemonte", "region/ITA/Lombardia", "region/ITA/Liguria"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(s.layers["answer"].highlights.len(), 3);
    }

    #[test]
    fn style_override_parses() {
        let src = r##"
[layers.base]
features = ["country/DEU"]
[layers.answer]
highlights = ["admin1/DEU/Bavaria"]
[layers.answer.style]
fill = "#3388ff"
stroke = "#1a5599"
"##;
        let s = parse_map_spec(src).unwrap();
        let style = s.layers["answer"].style.as_ref().unwrap();
        assert_eq!(style.fill.as_deref(), Some("#3388ff"));
        assert_eq!(style.stroke.as_deref(), Some("#1a5599"));
        assert!(style.stroke_width.is_none());
    }

    #[test]
    fn style_unknown_field_rejected() {
        let src = r#"
[layers.base]
features = ["country/DEU"]
[layers.answer]
highlights = ["admin1/DEU/Bavaria"]
[layers.answer.style]
bogus = true
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::Toml(_)), "got: {err:?}");
    }
}
