//! End-to-end map render pipeline.
//!
//! ```text
//! spec → cache key → cached? → load assets → embed
//!                    ↓ no
//!                    resolve → pick canvas → project → compose → style → write cache → embed
//! ```
//!
//! Returns a [`marki_core::RenderedBlock`] ready for the daemon to
//! splice into a card and upload to Anki.
//!
//! ## Canvas sizing
//!
//! The author's `size = [W, H]` is treated as a *max budget*: the
//! renderer projects the bbox under Mercator, computes its aspect
//! ratio, and chooses the largest canvas with that aspect that still
//! fits inside `[W, H]`. This avoids letterboxing — a wide region with
//! a square budget renders as `W × (W / aspect)`, not as `W × H` with
//! blank top/bottom strips.

use crate::cache::{self, CacheFile};
use crate::compose::{Feature, compose_layer};
use crate::data::{natural_earth, overpass};
use crate::dsl::{MapSpec, RevealMode};
use crate::embed::{EmbedLayer, embed_layers, resolve_reveals};
use crate::error::MapError;
use crate::geometry::{BBox, Geometry};
use crate::hash::cache_key;
use crate::project::{Mercator, Projector};
use crate::sidecar::{Sidecar, SidecarLayer};
use crate::style::load as load_theme;
use marki_core::{AssetMime, EmittedAsset, RenderedBlock};
use std::collections::BTreeMap;
use std::path::Path;

/// One resolved layer with its resolved geometry features.
struct ResolvedLayer<'a> {
    name: &'a str,
    /// (geometry, role, is_context) triples. `is_context` features are
    /// drawn but excluded from the viewport bbox computation.
    features: Vec<(Geometry, &'static str, bool)>,
}

/// Run the full pipeline for one [`MapSpec`].
///
/// `cache_root` is the daemon's cache dir (typically
/// `$XDG_CACHE_HOME/marki/`). Within it, this function reads/writes
/// `render/<key>/`.
///
/// On a cache hit, the SVGs and sidecar are read directly from disk
/// and no resolve / project / compose work happens.
pub fn run(spec: &MapSpec, cache_root: &Path) -> Result<RenderedBlock, MapError> {
    let theme = load_theme(&spec.style)?;
    let key = cache_key(spec, &theme.bytes)?;

    if cache::is_ready(cache_root, &key) {
        return load_from_cache(spec, cache_root, &key);
    }

    // ---- Resolve.
    let resolved = resolve_all_layers(spec, cache_root)?;

    // ---- Compute padded bbox + render-time canvas dimensions.
    let padded = combined_bbox(&resolved)?.padded(0.05);
    let aspect = Mercator::projected_aspect(padded);
    let (render_w, render_h) = fit_canvas(spec.size, aspect);
    let projector: Box<dyn Projector> =
        Box::new(Mercator::fit(padded, (render_w as f64, render_h as f64)));
    let projection_name = "mercator";

    // ---- Compose: one SVG per layer.
    let mut svg_files: Vec<(String, String, Vec<u8>)> = Vec::new();
    let reveals = resolve_reveals(&spec.layers);
    for layer in &resolved {
        let features: Vec<Feature<'_>> = layer
            .features
            .iter()
            .map(|(g, role, _is_context)| Feature { geom: g, role })
            .collect();
        // Only the base layer gets the opaque background; overlay
        // layers must be transparent so the base shows through.
        let mut layer_style = theme.style.clone();
        if layer.name != "base" {
            layer_style.background = None;
        }
        // Apply per-layer highlight style overrides from the DSL.
        if let Some(ov) = &spec.layers[layer.name].style {
            if let Some(role) = layer_style.roles.iter_mut().find(|r| r.role == "highlight") {
                if let Some(f) = &ov.fill { role.fill = f.clone(); }
                if let Some(s) = &ov.stroke { role.stroke = s.clone(); }
                if let Some(sw) = ov.stroke_width { role.stroke_width = sw; }
            }
        }
        let svg = compose_layer(
            render_w,
            render_h,
            &layer_style,
            &*projector,
            &features,
        );
        let cache_filename = format!("{}.svg", layer.name);
        svg_files.push((layer.name.to_string(), cache_filename, svg.into_bytes()));
    }

    // ---- Sidecar.
    let sidecar = Sidecar {
        width: render_w,
        height: render_h,
        requested_size: spec.size,
        projection: projection_name.into(),
        layers: svg_files
            .iter()
            .map(|(name, _cache_name, _bytes)| SidecarLayer {
                name: name.clone(),
                filename: layer_media_filename(&key, name),
                reveal: reveals.get(name).copied().unwrap_or(RevealMode::Fade),
            })
            .collect(),
    };
    let sidecar_bytes = crate::sidecar::render(&sidecar)
        .map_err(|e| MapError::Internal(format!("sidecar: {e}")))?;

    // ---- Persist to cache (atomic).
    let mut files: Vec<CacheFile<'_>> = svg_files
        .iter()
        .map(|(_name, cache_name, bytes)| CacheFile {
            name: cache_name.as_str(),
            bytes: bytes.as_slice(),
        })
        .collect();
    files.push(CacheFile {
        name: "sidecar.json",
        bytes: &sidecar_bytes,
    });
    cache::write_atomic(cache_root, &key, &files)?;

    // ---- Build embed + assets.
    Ok(build_block(
        &key,
        render_w,
        render_h,
        &reveals,
        &svg_files,
        &sidecar_bytes,
    ))
}

/// Pick the largest `(w, h)` within `budget` whose aspect equals
/// `aspect = projected_dx / projected_dy`. Both dimensions are clamped
/// to at least `1`.
///
/// ```text
/// budget = [600, 400], aspect = 2.0   →   (600, 300)   // width-bound
/// budget = [600, 400], aspect = 0.5   →   (200, 400)   // height-bound
/// budget = [600, 400], aspect = 1.5   →   (600, 400)   // matches
/// ```
fn fit_canvas(budget: [u32; 2], aspect: f64) -> (u32, u32) {
    let max_w = budget[0] as f64;
    let max_h = budget[1] as f64;
    // Try height-bound first: w = h * aspect.
    let cand_w = max_h * aspect;
    let (w, h) = if cand_w <= max_w {
        (cand_w, max_h)
    } else {
        // Width-bound: h = w / aspect.
        (max_w, max_w / aspect)
    };
    (w.round().max(1.0) as u32, h.round().max(1.0) as u32)
}

/// Compute the Anki-media filename for one layer. The content-addressed
/// cache key prevents collisions between cards.
fn layer_media_filename(key: &str, layer_name: &str) -> String {
    format!("marki-map-{key}-{layer_name}.svg")
}

fn sidecar_media_filename(key: &str) -> String {
    format!("marki-map-{key}-sidecar.json")
}

fn resolve_all_layers<'a>(
    spec: &'a MapSpec,
    cache_root: &Path,
) -> Result<Vec<ResolvedLayer<'a>>, MapError> {
    let mut out = Vec::with_capacity(spec.layers.len());
    for (name, lspec) in &spec.layers {
        let mut features: Vec<(Geometry, &'static str, bool)> = Vec::new();
        for r in &lspec.features {
            let role = role_for_feature_ref(r, name);
            let g = resolve_one(r, cache_root)?;
            features.push((g, role, false));
        }
        for r in &lspec.context {
            let role = role_for_feature_ref(r, name);
            let g = resolve_one(r, cache_root)?;
            features.push((g, role, true));
        }
        for h in &lspec.highlights {
            let g = resolve_one(h, cache_root)?;
            features.push((g, "highlight", false));
        }
        out.push(ResolvedLayer {
            name,
            features,
        });
    }
    Ok(out)
}

/// Resolve one feature reference. Centralised here so future sources
/// (Overpass, etc.) can be added without touching natural_earth.rs.
fn resolve_one(r: &str, cache_root: &Path) -> Result<Geometry, MapError> {
    if r == "coastline"
        || r.starts_with("country/")
        || r.starts_with("admin1/")
        || r.starts_with("region/")
        || r.starts_with("neighbors/")
        || r.starts_with("continent/")
        || r.starts_with("subregion/")
    {
        return natural_earth::resolve_feature(r);
    }
    if r.starts_with("relation/") || r.starts_with("way/") {
        return overpass::resolve(r, cache_root);
    }
    Err(MapError::Resolve(format!("unsupported feature ref: {r}")))
}

/// Pick a stylistic role for a feature reference based on what kind of
/// reference it is and which layer it lives on. Authors typically don't
/// need to think about roles directly.
fn role_for_feature_ref(r: &str, layer_name: &str) -> &'static str {
    if r == "coastline" {
        return "coast";
    }
    if r.starts_with("neighbors/") {
        return "neighbor";
    }
    if layer_name == "base" {
        "outline"
    } else {
        "highlight"
    }
}

fn combined_bbox(layers: &[ResolvedLayer<'_>]) -> Result<BBox, MapError> {
    let mut bb = BBox::empty();
    for l in layers {
        for (g, _, is_context) in &l.features {
            if !is_context {
                bb.extend(g.bbox());
            }
        }
    }
    if bb.is_empty() {
        return Ok(BBox {
            min_lon: -180.0,
            min_lat: -85.0,
            max_lon: 180.0,
            max_lat: 85.0,
        });
    }
    Ok(bb)
}

fn build_block(
    key: &str,
    render_w: u32,
    render_h: u32,
    reveals: &BTreeMap<String, RevealMode>,
    svg_files: &[(String, String, Vec<u8>)],
    sidecar_bytes: &[u8],
) -> RenderedBlock {
    let media_files: Vec<(String, String)> = svg_files
        .iter()
        .map(|(name, _cache_name, _)| {
            (
                name.clone(),
                layer_media_filename(key, name),
            )
        })
        .collect();

    let mut layers: Vec<EmbedLayer<'_>> = media_files
        .iter()
        .map(|(name, fname)| EmbedLayer {
            name: name.as_str(),
            media_filename: fname.as_str(),
            reveal: reveals.get(name).copied().unwrap_or(RevealMode::Fade),
        })
        .collect();
    let embed = embed_layers(render_w, render_h, &layers);

    let mut assets: Vec<EmittedAsset> = svg_files
        .iter()
        .map(|(name, _cache_name, bytes)| EmittedAsset {
            filename: layer_media_filename(key, name),
            bytes: bytes.clone(),
            mime: AssetMime::SvgXml,
        })
        .collect();
    assets.push(EmittedAsset {
        filename: sidecar_media_filename(key),
        bytes: sidecar_bytes.to_vec(),
        mime: AssetMime::ApplicationJson,
    });

    RenderedBlock {
        front_html: embed.front_html,
        back_html_extras: embed.back_html_extras,
        assets,
    }
}

fn load_from_cache(
    spec: &MapSpec,
    cache_root: &Path,
    key: &str,
) -> Result<RenderedBlock, MapError> {
    let names = cache::list_files(cache_root, key)?;
    let mut svg_files: Vec<(String, String, Vec<u8>)> = Vec::new();
    let mut sidecar_bytes: Vec<u8> = Vec::new();
    for n in names {
        let bytes = cache::read_file(cache_root, key, &n)?;
        if n == "sidecar.json" {
            sidecar_bytes = bytes;
            continue;
        }
        if let Some(stem) = n.strip_suffix(".svg") {
            svg_files.push((stem.to_string(), n.clone(), bytes));
        }
    }
    // Recover the actual rendered dimensions from the cached sidecar.
    // Falling back to `spec.size` would be wrong here — the cached
    // SVGs were composed at the autosized canvas, not the budget.
    let parsed: Sidecar = serde_json::from_slice(&sidecar_bytes)
        .map_err(|e| MapError::Internal(format!("sidecar parse: {e}")))?;
    let reveals = resolve_reveals(&spec.layers);
    Ok(build_block(
        key,
        parsed.width,
        parsed.height,
        &reveals,
        &svg_files,
        &sidecar_bytes,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn role_for_feature_ref_assignments() {
        assert_eq!(role_for_feature_ref("coastline", "base"), "coast");
        assert_eq!(role_for_feature_ref("country/DEU", "base"), "outline");
        assert_eq!(role_for_feature_ref("country/DEU", "answer"), "highlight");
        assert_eq!(role_for_feature_ref("neighbors/DEU", "answer"), "neighbor");
    }

    #[test]
    fn fit_canvas_widthbound() {
        // Wide aspect (2:1) inside a square budget → width-bound.
        let (w, h) = fit_canvas([400, 400], 2.0);
        assert_eq!((w, h), (400, 200));
    }

    #[test]
    fn fit_canvas_heightbound() {
        // Tall aspect (1:2) inside a square budget → height-bound.
        let (w, h) = fit_canvas([400, 400], 0.5);
        assert_eq!((w, h), (200, 400));
    }

    #[test]
    fn fit_canvas_matches_budget_when_aspect_fits() {
        // Budget aspect (1.5) matches data aspect → use whole budget.
        let (w, h) = fit_canvas([600, 400], 1.5);
        assert_eq!((w, h), (600, 400));
    }

    #[test]
    fn fit_canvas_clamps_to_one() {
        // Pathological: aspect so extreme that one dim rounds to 0.
        let (w, h) = fit_canvas([1, 1000], 0.0001);
        assert!(w >= 1 && h >= 1);
    }
}
