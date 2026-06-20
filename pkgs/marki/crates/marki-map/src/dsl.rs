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
//! highlights = ["adm1/DEU/Bayern"]
//! reveal = "fade"           # optional; non-base layers default to fade
//! ```
//!
//! A *hull layer* wraps hard-to-spot landmasses in a rounded convex
//! hull instead of drawing outlines:
//!
//! ```toml
//! [layers.halo]
//! [layers.halo.hull]
//! features = ["country/FJI"]   # rounded hull around the whole feature
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

    /// Viewport-tuning knobs. Defaults trim sparse Mercator-stretched
    /// edges (e.g. northern Norway on a Europe map) and exclude
    /// outlying components from clustering. See [`ViewportSpec`].
    #[serde(default)]
    pub viewport: ViewportSpec,

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

/// Per-card viewport tuning.
///
/// All fields are optional and have sensible defaults that match the
/// behaviour you'd expect for typical country/region cards. Override
/// them in TOML when the auto-framing produces something off:
///
/// ```toml
/// [viewport]
/// min_density = 0.10     # crop more aggressively
/// min_aspect = 0.8       # never go narrower than 4:5
/// cluster_factor = 0.3   # include far islands (Alaska, Iceland) in viewport
/// min_island_px = 0.0    # disable small-landmass culling
/// simplify_px = 0.0      # disable outline simplification
/// ```
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct ViewportSpec {
    /// Trim latitude/longitude edges with cumulative geometry density
    /// below this fraction. Default `0.0` (disabled — opt-in only).
    /// Set to a small positive value (e.g. `0.05`) to crop sparse
    /// edges; useful when a feature's bbox extends well beyond its
    /// dense interior. Tends to over-crop for natural country shapes,
    /// so it's off by default.
    #[serde(default = "default_min_density")]
    pub min_density: f64,

    /// Hard Mercator aspect ratio floor. After density trimming, if
    /// the viewport is still narrower than this, additional latitude
    /// is trimmed from whichever edge is furthest from the equator.
    /// Default `0.0` (disabled). Set to e.g. `0.6` if you want to
    /// force a less-tall canvas for high-latitude regions.
    #[serde(default = "default_min_aspect")]
    pub min_aspect: f64,

    /// Cluster threshold for excluding outlying components from the
    /// viewport. Polygons within `cluster_factor × seed_diagonal` of
    /// the cluster join it; further-away components are drawn but
    /// fall outside the viewport. Default `0.15`.
    #[serde(default = "default_cluster_factor")]
    pub cluster_factor: f64,

    /// Cull threshold for tiny disconnected landmasses, as a side
    /// length in rendered pixels (the area threshold is its square).
    /// A polygon component of a feature is dropped only when it is
    /// *both* smaller than `min_island_px²` *and* small relative to
    /// the feature's largest component (see `island_rel_frac`); the
    /// largest component of every feature is always kept. This removes
    /// the hundreds of sub-pixel specks that archipelago/subregion
    /// features otherwise emit, without garbage-collecting a small
    /// island that is itself the answer. Default `2.0`; set `0.0` to
    /// disable culling entirely.
    #[serde(default = "default_min_island_px")]
    pub min_island_px: f64,

    /// Relative-size escape hatch for culling: a component is kept,
    /// regardless of `min_island_px`, when its area is at least this
    /// fraction of the feature's largest component. Keeps clusters of
    /// roughly equal-sized islands intact while still dropping small
    /// islands that sit next to one dominant landmass. Default `0.05`.
    #[serde(default = "default_island_rel_frac")]
    pub island_rel_frac: f64,

    /// Douglas-Peucker simplification tolerance in rendered pixels.
    /// Vertices deviating less than this from the simplified outline
    /// are removed. Because coordinates are projected pixels this
    /// auto-adapts to zoom. Default `1.5`; set `0.0` to disable
    /// simplification and keep full vertex detail.
    #[serde(default = "default_simplify_px")]
    pub simplify_px: f64,
}

impl Default for ViewportSpec {
    fn default() -> Self {
        Self {
            min_density: default_min_density(),
            min_aspect: default_min_aspect(),
            cluster_factor: default_cluster_factor(),
            min_island_px: default_min_island_px(),
            island_rel_frac: default_island_rel_frac(),
            simplify_px: default_simplify_px(),
        }
    }
}

fn default_min_density() -> f64 { 0.0 }
fn default_min_aspect() -> f64 { 0.0 }
fn default_cluster_factor() -> f64 { 0.15 }
fn default_min_island_px() -> f64 { 2.0 }
fn default_island_rel_frac() -> f64 { 0.05 }
fn default_simplify_px() -> f64 { 1.5 }

/// One named layer inside a map block.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct LayerSpec {
    /// Geometry references to draw on this layer. Each entry is a
    /// short string like `coastline`, `country/DEU`,
    /// `adm1/DEU/Bayern`, or `relation/2145268`.
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
    /// Unset fields inherit from the active theme. On a hull layer the
    /// same overrides apply to the `hull` role.
    #[serde(default)]
    pub style: Option<HighlightStyle>,

    /// Makes this a *hull layer*: instead of drawing outlines, each
    /// referenced feature is wrapped in a rounded convex hull — the
    /// convex hull of its vertices, expanded outward with rounded
    /// corners — enclosing the feature's whole extent (every island of
    /// an archipelago) in one smooth region. Use it to make hard-to-spot
    /// landmasses (tiny Pacific/Caribbean island nations) findable.
    /// Stacking and reveal follow the normal layer rules — place the
    /// hull layer wherever you want it in TOML source order.
    #[serde(default)]
    pub hull: Option<HullSpec>,
}

/// Configuration for a hull layer. The outward padding (and corner
/// radius) is computed at render time as `clamp(radius ×
/// viewport_diagonal, min_px, max_frac × viewport_diagonal)`, so the
/// hull keeps a roughly constant, always-spottable margin around the
/// feature with `min_px` as a hard floor.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct HullSpec {
    /// Feature references to wrap in a hull. Polygon features only;
    /// line/point references (e.g. `coastline`) have no area and are
    /// skipped.
    #[serde(default)]
    pub features: Vec<String>,

    /// Outward padding (and corner radius) as a fraction of the viewport
    /// diagonal. Default `0.04`.
    #[serde(default = "default_hull_radius")]
    pub radius: f64,

    /// Hard pixel floor for the padding, so tiny islands on a zoomed-out
    /// map still get a visible hull. Default `10.0`.
    #[serde(default = "default_hull_min_px")]
    pub min_px: f64,

    /// Cap on the padding as a fraction of the viewport diagonal, so a
    /// feature that fills the canvas doesn't get a giant margin. Default
    /// `0.20`.
    #[serde(default = "default_hull_max_frac")]
    pub max_frac: f64,
}

impl Default for HullSpec {
    fn default() -> Self {
        Self {
            features: Vec::new(),
            radius: default_hull_radius(),
            min_px: default_hull_min_px(),
            max_frac: default_hull_max_frac(),
        }
    }
}

fn default_hull_radius() -> f64 { 0.04 }
fn default_hull_min_px() -> f64 { 10.0 }
fn default_hull_max_frac() -> f64 { 0.20 }

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
    #[error("size dimensions must be <= 10000 (got {0}x{1})")]
    SizeTooLarge(u32, u32),
    #[error("{field} must be between 0.0 and 1.0 (got {value})")]
    OutOfRange { field: &'static str, value: f64 },
    #[error("hull min_px must be >= 0 (got {0})")]
    HullMinPx(f64),
    #[error("hull radius ({radius}) must not exceed max_frac ({max_frac})")]
    HullRadiusOverMax { radius: f64, max_frac: f64 },
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
    if spec.size[0] > 10000 || spec.size[1] > 10000 {
        return Err(DslError::SizeTooLarge(spec.size[0], spec.size[1]));
    }
    let vp = &spec.viewport;
    if !(0.0..=1.0).contains(&vp.min_density) {
        return Err(DslError::OutOfRange { field: "min_density", value: vp.min_density });
    }
    if !(0.0..=1.0).contains(&vp.min_aspect) {
        return Err(DslError::OutOfRange { field: "min_aspect", value: vp.min_aspect });
    }
    if !(0.0..=1.0).contains(&vp.cluster_factor) {
        return Err(DslError::OutOfRange { field: "cluster_factor", value: vp.cluster_factor });
    }
    if vp.min_island_px < 0.0 {
        return Err(DslError::OutOfRange { field: "min_island_px", value: vp.min_island_px });
    }
    if !(0.0..=1.0).contains(&vp.island_rel_frac) {
        return Err(DslError::OutOfRange { field: "island_rel_frac", value: vp.island_rel_frac });
    }
    if vp.simplify_px < 0.0 {
        return Err(DslError::OutOfRange { field: "simplify_px", value: vp.simplify_px });
    }
    for lspec in spec.layers.values() {
        if let Some(hull) = &lspec.hull {
            if !(0.0..=1.0).contains(&hull.radius) {
                return Err(DslError::OutOfRange { field: "hull radius", value: hull.radius });
            }
            if !(0.0..=1.0).contains(&hull.max_frac) {
                return Err(DslError::OutOfRange { field: "hull max_frac", value: hull.max_frac });
            }
            if hull.min_px < 0.0 {
                return Err(DslError::HullMinPx(hull.min_px));
            }
            if hull.radius > hull.max_frac {
                return Err(DslError::HullRadiusOverMax {
                    radius: hull.radius,
                    max_frac: hull.max_frac,
                });
            }
        }
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
highlights = ["adm1/DEU/Bayern"]
"#;
        let s = parse_map_spec(src).unwrap();
        let answer = &s.layers["answer"];
        assert_eq!(answer.highlights, vec!["adm1/DEU/Bayern"]);
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
highlights = ["adm2/ITA/Piemonte", "adm2/ITA/Lombardia", "adm2/ITA/Liguria"]
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
highlights = ["adm1/DEU/Bayern"]
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
highlights = ["adm1/DEU/Bayern"]
[layers.answer.style]
bogus = true
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::Toml(_)), "got: {err:?}");
    }

    // ---------- viewport ----------

    #[test]
    fn viewport_defaults_when_absent() {
        let src = r#"
[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(s.viewport.min_density, 0.0);
        assert_eq!(s.viewport.min_aspect, 0.0);
        assert!((s.viewport.cluster_factor - 0.15).abs() < 1e-9);
        assert!((s.viewport.min_island_px - 2.0).abs() < 1e-9);
        assert!((s.viewport.island_rel_frac - 0.05).abs() < 1e-9);
        assert!((s.viewport.simplify_px - 1.5).abs() < 1e-9);
    }

    #[test]
    fn viewport_detail_fields_parse() {
        let src = r#"
[viewport]
min_island_px = 4.0
island_rel_frac = 0.1
simplify_px = 0.0
[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert!((s.viewport.min_island_px - 4.0).abs() < 1e-9);
        assert!((s.viewport.island_rel_frac - 0.1).abs() < 1e-9);
        assert_eq!(s.viewport.simplify_px, 0.0);
    }

    #[test]
    fn min_island_px_negative_rejected() {
        let src = r#"
[viewport]
min_island_px = -1.0
[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "min_island_px", .. }), "got: {err:?}");
    }

    #[test]
    fn island_rel_frac_out_of_range_rejected() {
        let src = r#"
[viewport]
island_rel_frac = 1.5
[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "island_rel_frac", .. }), "got: {err:?}");
    }

    #[test]
    fn simplify_px_negative_rejected() {
        let src = r#"
[viewport]
simplify_px = -0.5
[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "simplify_px", .. }), "got: {err:?}");
    }

    #[test]
    fn viewport_section_parses() {
        let src = r#"
[viewport]
min_density = 0.10
min_aspect = 0.8
cluster_factor = 0.3

[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert!((s.viewport.min_density - 0.10).abs() < 1e-9);
        assert!((s.viewport.min_aspect - 0.8).abs() < 1e-9);
        assert!((s.viewport.cluster_factor - 0.3).abs() < 1e-9);
    }

    #[test]
    fn viewport_partial_fields() {
        // Only override one field; the rest should default.
        let src = r#"
[viewport]
min_density = 0.05

[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert_eq!(s.viewport.min_density, 0.05);
        assert_eq!(s.viewport.min_aspect, 0.0);
        assert!((s.viewport.cluster_factor - 0.15).abs() < 1e-9);
    }

    #[test]
    fn viewport_unknown_field_rejected() {
        let src = r#"
[viewport]
bogus_field = 0.5

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::Toml(_)), "got: {err:?}");
    }

    // ---------- range validation ----------

    #[test]
    fn min_density_out_of_range() {
        let src = r#"
[viewport]
min_density = 1.5

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "min_density", .. }), "got: {err:?}");
    }

    #[test]
    fn min_density_negative() {
        let src = r#"
[viewport]
min_density = -0.1

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "min_density", .. }), "got: {err:?}");
    }

    #[test]
    fn min_aspect_out_of_range() {
        let src = r#"
[viewport]
min_aspect = 2.0

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "min_aspect", .. }), "got: {err:?}");
    }

    #[test]
    fn cluster_factor_out_of_range() {
        let src = r#"
[viewport]
cluster_factor = -0.5

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "cluster_factor", .. }), "got: {err:?}");
    }

    #[test]
    fn size_too_large() {
        let src = r#"
size = [20000, 400]

[layers.base]
features = ["coastline"]
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::SizeTooLarge(20000, 400)), "got: {err:?}");
    }

    #[test]
    fn boundary_values_valid() {
        // All at 1.0 boundary should be OK.
        let src = r#"
[viewport]
min_density = 1.0
min_aspect = 1.0
cluster_factor = 1.0

[layers.base]
features = ["coastline"]
"#;
        parse_map_spec(src).unwrap();

        // Size at 10000 boundary should be OK.
        let src2 = r#"
size = [10000, 10000]

[layers.base]
features = ["coastline"]
"#;
        parse_map_spec(src2).unwrap();
    }

    // ---------- hull ----------

    #[test]
    fn hull_layer_parses_with_defaults() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/FJI"]
"#;
        let s = parse_map_spec(src).unwrap();
        let hull = s.layers["halo"].hull.as_ref().unwrap();
        assert_eq!(hull.features, vec!["country/FJI".to_string()]);
        assert!((hull.radius - 0.04).abs() < 1e-9);
        assert!((hull.min_px - 10.0).abs() < 1e-9);
        assert!((hull.max_frac - 0.20).abs() < 1e-9);
    }

    #[test]
    fn hull_absent_by_default() {
        let src = r#"
[layers.base]
features = ["coastline"]
"#;
        let s = parse_map_spec(src).unwrap();
        assert!(s.layers["base"].hull.is_none());
    }

    #[test]
    fn hull_knobs_parse() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/TON"]
radius = 0.06
min_px = 14
max_frac = 0.3
"#;
        let s = parse_map_spec(src).unwrap();
        let hull = s.layers["halo"].hull.as_ref().unwrap();
        assert!((hull.radius - 0.06).abs() < 1e-9);
        assert!((hull.min_px - 14.0).abs() < 1e-9);
        assert!((hull.max_frac - 0.3).abs() < 1e-9);
    }

    #[test]
    fn hull_unknown_field_rejected() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/FJI"]
bogus = 1
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::Toml(_)), "got: {err:?}");
    }

    #[test]
    fn hull_radius_out_of_range() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/FJI"]
radius = 1.5
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::OutOfRange { field: "hull radius", .. }), "got: {err:?}");
    }

    #[test]
    fn hull_min_px_negative() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/FJI"]
min_px = -1
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::HullMinPx(_)), "got: {err:?}");
    }

    #[test]
    fn hull_radius_over_max_frac_rejected() {
        let src = r#"
[layers.base]
features = ["coastline"]

[layers.halo.hull]
features = ["country/FJI"]
radius = 0.3
max_frac = 0.2
"#;
        let err = parse_map_spec(src).unwrap_err();
        assert!(matches!(err, DslError::HullRadiusOverMax { .. }), "got: {err:?}");
    }
}
