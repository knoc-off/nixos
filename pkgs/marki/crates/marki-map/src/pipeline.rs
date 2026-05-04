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
use crate::clip;
use crate::cluster;
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
use crate::unwrap;
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
    let mut resolved = resolve_all_layers(spec, cache_root)?;

    // ---- Pick the optimal central meridian.
    //
    // We do this in two passes so outlying components (French
    // Polynesia, Hawaii, Chatham Islands, …) don't pollute the
    // choice of frame. The cluster heuristic in `viewport_bbox`
    // already filters them out by area; we just call it first on
    // the unrotated coordinates and use the resulting bbox's
    // longitude midpoint as the central meridian. The wrap meridian
    // (central ± 180°) ends up safely on the far side of the globe
    // from the data we care about.
    let rough_bb = viewport_bbox(&resolved)?;
    let central = (rough_bb.min_lon + rough_bb.max_lon) * 0.5;

    // ---- Rotate every geometry into the chosen frame, then split
    //      any rings that cross the wrap meridian. After this, no
    //      ring has a 360°-jump teleportation edge, so the SVG
    //      composer can draw clean paths.
    if central.abs() > f64::EPSILON {
        for layer in &mut resolved {
            for (g, _, _) in &mut layer.features {
                unwrap::rotate_geometry(g, central);
            }
        }
    }
    for layer in &mut resolved {
        for (g, _, _) in &mut layer.features {
            let old = std::mem::take(g);
            *g = unwrap::split_at_wrap(old, central);
        }
    }

    // ---- Compute padded bbox + render-time canvas dimensions.
    //      Viewport focuses on the main cluster of features; outlying
    //      components (Alaska on a USA-without-highlight map, Hawaii
    //      on USA, …) still get drawn but fall outside the viewBox.
    let padded = viewport_bbox(&resolved)?.padded(0.05);

    // ---- Clip every geometry to a 10% margin around the viewport.
    //      Components fully outside are dropped; straddling rings are
    //      clipped with Sutherland-Hodgman so they end with clean
    //      edges. 10% margin keeps S-H clip lines ~20–30 px off-
    //      canvas so they're never visible, while cutting geometry
    //      close to the viewport boundary for maximum SVG size
    //      reduction.
    let clip_bb = padded.padded(0.10);
    for layer in &mut resolved {
        for (g, _, _) in &mut layer.features {
            let old = std::mem::take(g);
            *g = clip::clip_geometry(old, clip_bb);
        }
    }

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

/// Viewport bbox using the "main cluster" heuristic.
///
/// Geometry is split into three buckets by purpose:
///   * **focus** features (non-context, non-highlight) — the base
///     geometry whose dominant landmass should fill the canvas.
///   * **highlights** — always stretch the viewport to include them
///     (so a Hawaii highlight on a USA base correctly spans the
///     Pacific).
///   * **context** — drawn but excluded from the viewport entirely.
///
/// Focus features go through [`cluster::main_cluster_bbox`] which picks
/// the largest connected cluster of polygon components; Hawaii / French
/// Guiana / Chatham Islands are drawn but clipped by the viewBox.
fn viewport_bbox(layers: &[ResolvedLayer<'_>]) -> Result<BBox, MapError> {
    let mut focus: Vec<&Geometry> = Vec::new();
    let mut highlights: Vec<&Geometry> = Vec::new();
    for l in layers {
        for (g, role, is_context) in &l.features {
            if *is_context {
                continue;
            }
            if *role == "highlight" {
                highlights.push(g);
            } else {
                focus.push(g);
            }
        }
    }

    // 1. Each focus feature contributes its own main-cluster bbox.
    //    We cluster *per feature* (not on the unioned component pool)
    //    so multi-country composites (`subregion/Western Europe`) get
    //    their own cluster filtering, and a list of distinct countries
    //    (`country/DEU` + `country/ITA` + `country/ESP`) doesn't get
    //    pruned by the inter-country gap exceeding a single feature's
    //    cluster threshold. Falls back to the full bbox for line-only
    //    geometries (coastline) which have no polygon area.
    let mut bb = BBox::empty();
    for g in &focus {
        let g_bb = cluster::main_cluster_bbox(&[*g], cluster::DEFAULT_CLUSTER_FACTOR)
            .unwrap_or_else(|| g.bbox());
        bb.extend(g_bb);
    }

    // 2. Highlights stretch the viewport, also cluster-reduced
    //    individually so a multi-component highlight (e.g.
    //    `country/FJI`, which has islands on both sides of the
    //    antimeridian) doesn't blow the bbox up to a 360°-wide span.
    //    Single-component highlights collapse to a normal bbox.
    for g in &highlights {
        let g_bb = cluster::main_cluster_bbox(&[*g], cluster::DEFAULT_CLUSTER_FACTOR)
            .unwrap_or_else(|| g.bbox());
        bb.extend(g_bb);
    }

    if bb.is_empty() {
        // Nothing resolved (or only `context`) — fall back to a
        // standard world bbox so the renderer still produces something.
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
    // Read sidecar first — its `layers` array is the authoritative
    // source for layer order (written in TOML/IndexMap order during
    // the fresh render). Never rely on filesystem directory listing
    // order, which is alphabetical and would reorder layers.
    let sidecar_bytes = cache::read_file(cache_root, key, "sidecar.json")?;
    let parsed: Sidecar = serde_json::from_slice(&sidecar_bytes)
        .map_err(|e| MapError::Internal(format!("sidecar parse: {e}")))?;

    let mut svg_files: Vec<(String, String, Vec<u8>)> = Vec::new();
    for layer in &parsed.layers {
        let svg_name = format!("{}.svg", layer.name);
        let bytes = cache::read_file(cache_root, key, &svg_name)?;
        svg_files.push((layer.name.clone(), svg_name, bytes));
    }

    let reveals = resolve_reveals(&spec.layers);
    Ok(build_block(
        key,
        parsed.width,
        parsed.height,
        &reveals,
        &svg_files,
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

