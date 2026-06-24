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
use crate::compose::{Feature, RenderDetail, compose_layer};
use crate::data::{geoboundaries, natural_earth, overpass};
use crate::dsl::{MapSpec, RevealMode};
use crate::embed::{EmbedLayer, embed_layers, resolve_reveals};
use crate::error::MapError;
use crate::geometry::{BBox, Geometry, LonLat};
use crate::hash::cache_key;
use crate::project::{Mercator, Projector};
use crate::sidecar::{Sidecar, SidecarLayer};
use crate::style::load as load_theme;
use crate::trim;
use crate::unwrap;
use marki_core::{AssetMime, EmittedAsset, RenderedBlock};
use std::collections::BTreeMap;
use std::path::Path;

/// One resolved layer with its resolved geometry features.
struct ResolvedLayer<'a> {
    name: &'a str,
    /// (geometry, role, is_context, faithful) tuples. `is_context`
    /// features are drawn but excluded from the viewport bbox
    /// computation. `faithful` features (composites — continent /
    /// subregion / neighbours) skip per-feature outline simplification,
    /// which would otherwise re-split the coincident borders shared by
    /// adjacent member units into double lines.
    features: Vec<(Geometry, &'static str, bool, bool)>,
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
        tracing::debug!(key, "map cache hit");
        return load_from_cache(spec, cache_root, &key);
    }
    tracing::debug!(
        key,
        layers = spec.layers.len(),
        style = %spec.style,
        "map cache miss; rendering"
    );

    // ---- Resolve.
    let mut resolved = resolve_all_layers(spec, cache_root)?;
    if tracing::enabled!(tracing::Level::TRACE) {
        for l in &resolved {
            tracing::trace!(layer = %l.name, features = l.features.len(), "resolved layer");
        }
    }

    // ---- Pick the optimal central meridian.
    //
    // We choose the meridian that puts every non-context feature in the
    // smallest contiguous longitude window — i.e. the wrap meridian
    // (`central ± 180°`, where rings get cut) falls in the emptiest part
    // of the globe rather than through the data. A naive
    // midpoint-of-raw-bbox fails badly across the antimeridian: a card
    // spanning Melanesia (≈140°E) and Polynesia (≈−150°W) would pick a
    // central meridian in the Atlantic and smear the Pacific across
    // ~340° of canvas. See [`choose_central_meridian`].
    let central = choose_central_meridian(&resolved).unwrap_or(0.0);
    tracing::debug!(central, "chose central meridian");

    // ---- Rotate every geometry into the chosen frame, then split
    //      any rings that cross the wrap meridian. After this, no
    //      ring has a 360°-jump teleportation edge, so the SVG
    //      composer can draw clean paths.
    if central.abs() > f64::EPSILON {
        for layer in &mut resolved {
        for (g, _, _, _) in &mut layer.features {
                unwrap::rotate_geometry(g, central);
            }
        }
    }
    for layer in &mut resolved {
        for (g, _, _, _) in &mut layer.features {
            let old = std::mem::take(g);
            *g = unwrap::split_at_wrap(old, central);
        }
    }

    // ---- Compute padded bbox + render-time canvas dimensions.
    //      Viewport focuses on the main cluster of features; outlying
    //      components (Alaska on a USA-without-highlight map, Hawaii
    //      on USA, …) still get drawn but fall outside the viewBox.
    //      Density-based trimming then crops sparse Mercator-stretched
    //      edges (e.g. northern tip of Norway on a Europe map) so the
    //      canvas stays well-proportioned. Both behaviours are tunable
    //      via the `[viewport]` DSL section.
    let raw_bb = viewport_bbox(&resolved, spec.viewport.cluster_factor)?;
    let focus_geoms = collect_focus_geoms(&resolved);
    let trimmed = trim::trim_sparse_edges(
        raw_bb,
        &focus_geoms,
        spec.viewport.min_density,
        spec.viewport.min_aspect,
    );
    let padded = trimmed.padded(0.05);

    // ---- Clip every geometry to a 10% margin around the viewport.
    //      Components fully outside are dropped; straddling rings are
    //      clipped with Sutherland-Hodgman so they end with clean
    //      edges. 10% margin keeps S-H clip lines ~20–30 px off-
    //      canvas so they're never visible, while cutting geometry
    //      close to the viewport boundary for maximum SVG size
    //      reduction.
    let clip_bb = padded.padded(0.005);
    for layer in &mut resolved {
        for (g, _, _, _) in &mut layer.features {
            let old = std::mem::take(g);
            *g = clip::clip_geometry(old, clip_bb);
        }
    }

    let aspect = Mercator::projected_aspect(padded);
    let (render_w, render_h) = fit_canvas(spec.size, aspect);
    let projector: Box<dyn Projector> =
        Box::new(Mercator::fit(padded, (render_w as f64, render_h as f64)));
    let projection_name = "mercator";
    tracing::debug!(
        bbox_lon = format!("{:.2}..{:.2}", padded.min_lon, padded.max_lon),
        bbox_lat = format!("{:.2}..{:.2}", padded.min_lat, padded.max_lat),
        lon_span = format!("{:.1}", padded.max_lon - padded.min_lon),
        aspect = format!("{aspect:.3}"),
        canvas = format!("{render_w}x{render_h}"),
        "viewport + canvas resolved"
    );

    // ---- Compose: one SVG per layer.
    let detail = RenderDetail {
        min_island_px2: spec.viewport.min_island_px * spec.viewport.min_island_px,
        island_rel_frac: spec.viewport.island_rel_frac,
        simplify_px: spec.viewport.simplify_px,
    };
    let mut svg_files: Vec<(String, String, Vec<u8>)> = Vec::new();
    let reveals = resolve_reveals(&spec.layers);
    for layer in &resolved {
        let features: Vec<Feature<'_>> = layer
            .features
            .iter()
            .map(|(g, role, _is_context, faithful)| Feature {
                geom: g,
                role,
                faithful: *faithful,
            })
            .collect();
        // Only the base layer gets the opaque background; overlay
        // layers must be transparent so the base shows through.
        let mut layer_style = theme.style.clone();
        if layer.name != "base" {
            layer_style.background = None;
        }
        // Apply per-layer highlight style overrides from the DSL. On a
        // hull layer the same overrides target the `hull` role.
        if let Some(ov) = &spec.layers[layer.name].style {
            for role in layer_style
                .roles
                .iter_mut()
                .filter(|r| r.role == "highlight" || r.role == "hull")
            {
                if let Some(f) = &ov.fill {
                    role.fill = f.clone();
                }
                if let Some(s) = &ov.stroke {
                    role.stroke = s.clone();
                }
                if let Some(sw) = ov.stroke_width {
                    role.stroke_width = sw;
                }
            }
        }
        // Scale-aware halo radius: a fraction of the viewport diagonal,
        // floored at `min_px` and capped at `max_frac` of the diagonal.
        // Zero on non-hull layers (ignored by the composer).
        let hull_radius_px = match &spec.layers[layer.name].hull {
            Some(h) => {
                let diag =
                    ((render_w as f64).powi(2) + (render_h as f64).powi(2)).sqrt();
                // Cap at max_frac of the diagonal, then apply the min_px
                // floor last so the "always visible" guarantee wins even
                // on a tiny canvas where the cap would fall below it.
                (h.radius * diag).min(h.max_frac * diag).max(h.min_px)
            }
            None => 0.0,
        };
        let svg = compose_layer(
            render_w,
            render_h,
            &layer_style,
            &*projector,
            &features,
            hull_radius_px,
            detail,
        );
        tracing::trace!(
            layer = %layer.name,
            features = features.len(),
            hull_radius_px,
            svg_bytes = svg.len(),
            "composed layer"
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
    Ok(build_block(&key, render_w, render_h, &reveals, &svg_files))
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
        let mut features: Vec<(Geometry, &'static str, bool, bool)> = Vec::new();
        for r in &lspec.features {
            let role = role_for_feature_ref(r, name);
            let g = resolve_one(r, cache_root)?;
            features.push((g, role, false, is_composite_ref(r)));
        }
        for r in &lspec.context {
            let role = role_for_feature_ref(r, name);
            let g = resolve_one(r, cache_root)?;
            features.push((g, role, true, is_composite_ref(r)));
        }
        for h in &lspec.highlights {
            let g = resolve_one(h, cache_root)?;
            features.push((g, "highlight", false, is_composite_ref(h)));
        }
        if let Some(hull) = &lspec.hull {
            for r in &hull.features {
                let g = resolve_one(r, cache_root)?;
                features.push((g, "hull", false, is_composite_ref(r)));
            }
        }
        out.push(ResolvedLayer { name, features });
    }
    Ok(out)
}

/// Whether a feature ref is a composite — a continent, subregion or
/// neighbour set, each a concatenation of independently-keyed but
/// border-coincident member units (CGAZ). Composites must skip
/// per-feature outline simplification, which would split their shared
/// internal borders into double lines. (Island culling stays on — it
/// only drops whole disconnected specks, never a shared land border.)
fn is_composite_ref(r: &str) -> bool {
    r.starts_with("continent/")
        || r.starts_with("subregion/")
        || r.starts_with("neighbors/")
}

/// Resolve one feature reference. Centralised here so future sources
/// can be added without touching the per-source loaders.
fn resolve_one(r: &str, cache_root: &Path) -> Result<Geometry, MapError> {
    if r == "coastline" {
        return natural_earth::resolve_feature(r);
    }
    if r.starts_with("country/")
        || r.starts_with("adm1/")
        || r.starts_with("adm2/")
        || r.starts_with("adm3/")
        || r.starts_with("neighbors/")
        || r.starts_with("continent/")
        || r.starts_with("subregion/")
    {
        return geoboundaries::resolve_feature(r);
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

/// Collect the focus geometries (non-context, non-highlight) across
/// every layer. Used to feed [`trim::trim_sparse_edges`] which only
/// inspects the main subject geometry — context and highlights are
/// either explicitly background (`context`) or already accounted for
/// in `viewport_bbox`'s highlight-stretch step.
fn collect_focus_geoms<'a>(layers: &'a [ResolvedLayer<'_>]) -> Vec<&'a Geometry> {
    let mut out = Vec::new();
    for l in layers {
        for (g, role, is_context, _) in &l.features {
            if *is_context || *role == "highlight" || *role == "hull" {
                continue;
            }
            out.push(g);
        }
    }
    out
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
fn viewport_bbox(layers: &[ResolvedLayer<'_>], cluster_factor: f64) -> Result<BBox, MapError> {
    let mut focus: Vec<&Geometry> = Vec::new();
    let mut highlights: Vec<&Geometry> = Vec::new();
    for l in layers {
        for (g, role, is_context, _) in &l.features {
            if *is_context {
                continue;
            }
            if *role == "highlight" || *role == "hull" {
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
        let g_bb = cluster::main_cluster_bbox(&[*g], cluster_factor).unwrap_or_else(|| g.bbox());
        bb.extend(g_bb);
    }

    // 2. Highlights stretch the viewport, also cluster-reduced
    //    individually so a multi-component highlight (e.g.
    //    `country/FJI`, which has islands on both sides of the
    //    antimeridian) doesn't blow the bbox up to a 360°-wide span.
    //    Single-component highlights collapse to a normal bbox.
    for g in &highlights {
        let g_bb = cluster::main_cluster_bbox(&[*g], cluster_factor).unwrap_or_else(|| g.bbox());
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

/// Largest empty longitude gap below which a feature set is treated as
/// effectively global, so we don't rotate it. A world coastline (whose
/// Antarctica spans every meridian) has only sub-degree gaps; a Pacific
/// regional card has a gap of well over 200° across the Americas and
/// Atlantic. 60° comfortably separates the two.
const GLOBAL_GAP_THRESHOLD: f64 = 60.0;

/// Pick the central meridian that places every non-context feature in
/// the smallest contiguous longitude window.
///
/// Algorithm: collect every vertex longitude from focus/highlight/hull
/// features, find the largest circular gap between consecutive
/// longitudes, and put the wrap meridian in the middle of that gap. The
/// central meridian is then the antipode of the gap midpoint — the
/// centre of the occupied arc.
///
/// Returns `None` when there are no non-context vertices, or when the
/// data is effectively global (largest gap `< GLOBAL_GAP_THRESHOLD`);
/// the caller then falls back to `central = 0` (no rotation), which
/// preserves the natural framing of world maps.
///
/// Reduces to the raw-bbox midpoint for ordinary non-wrapping regions
/// (Europe → ≈15°E, CONUS → ≈−96°W).
fn choose_central_meridian(layers: &[ResolvedLayer<'_>]) -> Option<f64> {
    let mut lons: Vec<f64> = Vec::new();
    for l in layers {
        for (g, _role, is_context, _) in &l.features {
            if *is_context {
                continue;
            }
            for_each_vertex(g, &mut |p| lons.push(norm360(p.lon)));
        }
    }
    if lons.is_empty() {
        return None;
    }
    lons.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    // Largest circular gap between consecutive (sorted) longitudes,
    // including the wrap-around gap from the last back to the first.
    let n = lons.len();
    let mut max_gap = 0.0;
    let mut gap_mid = 0.0;
    for i in 0..n {
        let cur = lons[i];
        let next = if i + 1 < n { lons[i + 1] } else { lons[0] + 360.0 };
        let gap = next - cur;
        if gap > max_gap {
            max_gap = gap;
            gap_mid = cur + gap * 0.5;
        }
    }
    if max_gap < GLOBAL_GAP_THRESHOLD {
        // Data wraps most of the globe — no meaningful frame to centre.
        return None;
    }
    // Centre of the occupied arc is the antipode of the gap's middle.
    Some(norm180(gap_mid + 180.0))
}

/// Normalise a longitude to `[0, 360)`.
fn norm360(lon: f64) -> f64 {
    lon.rem_euclid(360.0)
}

/// Normalise a longitude to `(-180, 180]`.
fn norm180(lon: f64) -> f64 {
    let x = lon.rem_euclid(360.0);
    if x > 180.0 { x - 360.0 } else { x }
}

/// Visit every vertex of a geometry (all rings, all components).
fn for_each_vertex(g: &Geometry, f: &mut dyn FnMut(LonLat)) {
    match g {
        Geometry::Point(p) => f(*p),
        Geometry::LineString(line) => line.iter().for_each(|p| f(*p)),
        Geometry::MultiLineString(lines) => {
            lines.iter().flatten().for_each(|p| f(*p))
        }
        Geometry::Polygon { outer, holes } => {
            outer.iter().for_each(|p| f(*p));
            holes.iter().flatten().for_each(|p| f(*p));
        }
        Geometry::MultiPolygon(polys) => {
            for poly in polys {
                poly.outer.iter().for_each(|p| f(*p));
                poly.holes.iter().flatten().for_each(|p| f(*p));
            }
        }
    }
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
        .map(|(name, _cache_name, _)| (name.clone(), layer_media_filename(key, name)))
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

    /// Build a one-layer resolved set from `(geom, role, is_context)`
    /// triples for the central-meridian tests. Composites aren't
    /// exercised here, so `faithful` is always `false`.
    fn layer_with(
        feats: Vec<(Geometry, &'static str, bool)>,
    ) -> Vec<ResolvedLayer<'static>> {
        let feats = feats
            .into_iter()
            .map(|(g, role, ctx)| (g, role, ctx, false))
            .collect();
        vec![ResolvedLayer {
            name: "base",
            features: feats,
        }]
    }

    fn box_poly(min_lon: f64, max_lon: f64) -> Geometry {
        Geometry::Polygon {
            outer: vec![
                LonLat { lon: min_lon, lat: 0.0 },
                LonLat { lon: max_lon, lat: 0.0 },
                LonLat { lon: max_lon, lat: 5.0 },
                LonLat { lon: min_lon, lat: 5.0 },
                LonLat { lon: min_lon, lat: 0.0 },
            ],
            holes: vec![],
        }
    }

    #[test]
    fn central_meridian_europe_is_midpoint() {
        // −10°…40° → ≈15°E, same as the old raw-midpoint behaviour.
        let layers = layer_with(vec![(box_poly(-10.0, 40.0), "outline", false)]);
        let c = choose_central_meridian(&layers).unwrap();
        assert!((c - 15.0).abs() < 1.0, "got {c}");
    }

    #[test]
    fn central_meridian_conus_is_midpoint() {
        let layers = layer_with(vec![(box_poly(-125.0, -67.0), "outline", false)]);
        let c = choose_central_meridian(&layers).unwrap();
        assert!((c - -96.0).abs() < 1.0, "got {c}");
    }

    #[test]
    fn central_meridian_pacific_avoids_thin_strip() {
        // Melanesia (≈140–180°E) + Polynesia (≈−175…−150°W). The raw
        // midpoint would land near −10°E (Atlantic) and cut through the
        // Pacific. Largest-gap must instead centre on the Pacific so the
        // occupied window is small and contiguous.
        let layers = layer_with(vec![
            (box_poly(140.0, 180.0), "outline", false),
            (box_poly(-175.0, -150.0), "outline", false),
        ]);
        let c = choose_central_meridian(&layers).unwrap();
        // Centre of the occupied arc sits in the Pacific, ~175–185°E.
        let c360 = norm360(c);
        assert!(
            (c360 - 182.5).abs() < 10.0,
            "central {c} (norm360 {c360}) not Pacific-centred"
        );
        // And after rotating, the occupied span must be tight (< 180°),
        // not a globe-spanning strip.
        let occupied: Vec<f64> = [140.0, 180.0, -175.0, -150.0]
            .iter()
            .map(|&lon| norm180(lon - c))
            .collect();
        let span = occupied.iter().cloned().fold(f64::MIN, f64::max)
            - occupied.iter().cloned().fold(f64::MAX, f64::min);
        assert!(span < 180.0, "rotated span {span} still wraps the world");
    }

    #[test]
    fn central_meridian_single_fiji_is_pacific() {
        // Fiji straddles the dateline: bulk at ~178°E, a few at ~−178°W.
        let layers = layer_with(vec![(box_poly(177.0, 180.0), "highlight", false)]);
        let c = choose_central_meridian(&layers).unwrap();
        assert!((norm360(c) - 178.5).abs() < 5.0, "got {c}");
    }

    #[test]
    fn central_meridian_global_data_returns_none() {
        // A ring spanning every longitude (like a world coastline with
        // Antarctica) has only tiny gaps → no meaningful frame.
        let mut outer = Vec::new();
        let mut lon = -180.0;
        while lon < 180.0 {
            outer.push(LonLat { lon, lat: -80.0 });
            lon += 5.0;
        }
        outer.push(LonLat { lon: 175.0, lat: -70.0 });
        outer.push(LonLat { lon: -180.0, lat: -80.0 });
        let layers = layer_with(vec![(
            Geometry::Polygon { outer, holes: vec![] },
            "outline",
            false,
        )]);
        assert!(choose_central_meridian(&layers).is_none());
    }

    #[test]
    fn central_meridian_ignores_context() {
        // Only context features → no frame.
        let layers = layer_with(vec![(box_poly(0.0, 10.0), "outline", true)]);
        assert!(choose_central_meridian(&layers).is_none());
    }

    #[test]
    fn norm_helpers() {
        assert!((norm360(-10.0) - 350.0).abs() < 1e-9);
        assert!((norm360(370.0) - 10.0).abs() < 1e-9);
        assert!((norm180(190.0) - -170.0).abs() < 1e-9);
        assert!((norm180(185.0) - -175.0).abs() < 1e-9);
        assert!((norm180(-190.0) - 170.0).abs() < 1e-9);
        assert!((norm180(45.0) - 45.0).abs() < 1e-9);
        // 180 stays 180 (inclusive upper bound).
        assert!((norm180(180.0) - 180.0).abs() < 1e-9);
    }

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
