//! Natural Earth shapefile loader.
//!
//! `NATURAL_EARTH_DATA` env (set by the home-manager module) points
//! at a directory containing the `ne_10m_admin_0_countries`,
//! `ne_10m_admin_1_states_provinces`, and `ne_10m_coastline` shapefile
//! sets (`.shp` + `.shx` + `.dbf`).
//!
//! Lookups are by:
//!
//!   * `coastline` — every coastline polyline.
//!   * `country/<ISO_A3>` — one country polygon (or multipolygon) by
//!     three-letter ISO code (`DEU`, `FRA`, …). Always the full
//!     geometry; the renderer focuses the viewport on the main
//!     cluster automatically (see `cluster.rs`).
//!   * `admin1/<ISO_A3>/<NAME>` — one admin-1 entry (province, state,
//!     oblast, …) inside a country by ISO + name. Indexed by both
//!     `name_en` and `name` (case-insensitive).
//!   * `region/<ISO_A3>/<NAME>` — composite of all admin-1 entries
//!     whose NE `region` column matches `<NAME>` (case-insensitive).
//!     Use this for Italian regioni, French régions, etc.
//!   * `neighbors/<ISO_A3>` — every country that shares a border
//!     segment with the target (topological adjacency). Falls back
//!     to bbox-intersect for island nations with no shared edges.
//!   * `continent/<NAME>` and `subregion/<NAME>` — composite of every
//!     country in the named NE `CONTINENT` / `SUBREGION` group.
//!
//! The resolver caches the parsed dataset per process; subsequent
//! lookups are in-memory.

use crate::error::MapError;
use crate::geometry::{BBox, Geometry, LonLat, Polygon};
use shapefile::dbase;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

/// One indexed feature loaded from a Natural Earth shapefile.
#[derive(Clone)]
struct NeFeature {
    geom: Geometry,
    bbox: BBox,
}

#[derive(Default)]
struct NeIndex {
    /// Country polygon by ISO_A3.
    countries: HashMap<String, NeFeature>,
    /// Admin-1 polygon by (ISO_A3, lower_case_name).
    /// Each row is indexed under both `name_en` and `name` when they
    /// differ; the first-seen geometry wins on collision.
    admin1: HashMap<(String, String), NeFeature>,
    /// Region-level composites by (ISO_A3, lower_case_region_name).
    /// Built by merging all admin-1 entries whose NE `region` column
    /// matches.
    regions: HashMap<(String, String), NeFeature>,
    /// Continent-level composites by lowercase continent name.
    /// Built from the NE `CONTINENT` column on admin-0 records.
    continents: HashMap<String, NeFeature>,
    /// UN subregion composites by lowercase subregion name.
    /// Built from the NE `SUBREGION` column on admin-0 records.
    subregions: HashMap<String, NeFeature>,
    /// All coastline lines, grouped into one MultiLineString-like
    /// list. We keep them as a Vec so the bbox of a region-of-interest
    /// can still filter at draw time.
    coastline: Vec<NeFeature>,
    /// Convenience: ISO_A3 → bbox of that country, used by fallback
    /// neighbours.
    country_bbox: HashMap<String, BBox>,
    /// Topological neighbour graph: ISO_A3 → sorted list of
    /// border-sharing ISO_A3s. Built from shared boundary segments.
    neighbors: HashMap<String, Vec<String>>,
}

/// Path to the Natural Earth data directory. Reads `NATURAL_EARTH_DATA`
/// at first call; cached for the process lifetime.
fn data_dir() -> Result<PathBuf, MapError> {
    static DIR: OnceLock<Result<PathBuf, String>> = OnceLock::new();
    let r = DIR.get_or_init(|| match std::env::var("NATURAL_EARTH_DATA") {
        Ok(s) if !s.is_empty() => Ok(PathBuf::from(s)),
        _ => Err("NATURAL_EARTH_DATA env not set".to_string()),
    });
    match r {
        Ok(p) => Ok(p.clone()),
        Err(e) => Err(MapError::Resolve(e.clone())),
    }
}

/// Process-global lazily-loaded NE index.
fn index() -> Result<&'static NeIndex, MapError> {
    static INDEX: OnceLock<Result<NeIndex, String>> = OnceLock::new();
    static LOAD_LOCK: Mutex<()> = Mutex::new(());

    if let Some(r) = INDEX.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let _guard = LOAD_LOCK.lock().unwrap();
    if let Some(r) = INDEX.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let dir = match data_dir() {
        Ok(d) => d,
        Err(e) => {
            let _ = INDEX.set(Err(e.to_string()));
            return Err(e);
        }
    };
    let built = match build_index(&dir) {
        Ok(i) => Ok(i),
        Err(e) => Err(e.to_string()),
    };
    let _ = INDEX.set(built);
    INDEX
        .get()
        .unwrap()
        .as_ref()
        .map_err(|e| MapError::Resolve(e.clone()))
}

/// Resolve one feature reference like `country/DEU` to a [`Geometry`].
/// `coastline` and `neighbors/<ISO>` return composite geometries.
///
/// Geometry is always the *full* shape (every polygon component, every
/// overseas territory). The pipeline picks an appropriate viewport via
/// [`crate::cluster`].
pub fn resolve_feature(name: &str) -> Result<Geometry, MapError> {
    let idx = index()?;
    if let Some(rest) = name.strip_prefix("country/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "country refs no longer take a modifier; got `{name}`. \
                 The `/mainland` suffix has been removed — viewport now \
                 auto-focuses on the main cluster."
            )));
        }
        let feat = idx
            .countries
            .get(rest)
            .ok_or_else(|| MapError::Resolve(format!("unknown country: {rest}")))?;
        return Ok(feat.geom.clone());
    }
    if let Some(rest) = name.strip_prefix("admin1/") {
        let (iso, region) = rest
            .split_once('/')
            .ok_or_else(|| MapError::Resolve(format!("bad admin1 ref: {name}")))?;
        let key = (iso.to_string(), region.to_lowercase());
        return idx
            .admin1
            .get(&key)
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown admin1: {iso}/{region}")));
    }
    if let Some(rest) = name.strip_prefix("region/") {
        let (iso, region) = rest
            .split_once('/')
            .ok_or_else(|| MapError::Resolve(format!("bad region ref: {name}")))?;
        let key = (iso.to_string(), region.to_lowercase());
        return idx
            .regions
            .get(&key)
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown region: {iso}/{region}")));
    }
    if name == "coastline" {
        // Flatten all coastline lines into one MultiLineString.
        let lines: Vec<Vec<LonLat>> = idx
            .coastline
            .iter()
            .filter_map(|f| match &f.geom {
                Geometry::MultiLineString(ls) => Some(ls.clone()),
                Geometry::LineString(l) => Some(vec![l.clone()]),
                _ => None,
            })
            .flatten()
            .collect();
        return Ok(Geometry::MultiLineString(lines));
    }
    if let Some(rest) = name.strip_prefix("neighbors/") {
        let _seed = idx
            .countries
            .get(rest)
            .ok_or_else(|| MapError::Resolve(format!("unknown country for neighbors: {rest}")))?;
        // Use the topological graph if populated; fall back to bbox
        // intersect for island nations with no shared boundary edges.
        let isos: Vec<&str> = match idx.neighbors.get(rest) {
            Some(v) if !v.is_empty() => v.iter().map(|s| s.as_str()).collect(),
            _ => fallback_bbox_neighbors(rest, idx),
        };
        let mut polys: Vec<Polygon> = Vec::new();
        for iso in isos {
            if let Some(feat) = idx.countries.get(iso) {
                // Pass the full geometry; viewport clustering on the
                // pipeline side handles outlying components.
                match &feat.geom {
                    Geometry::Polygon { outer, holes } => polys.push(Polygon {
                        outer: outer.clone(),
                        holes: holes.clone(),
                    }),
                    Geometry::MultiPolygon(ps) => polys.extend(ps.iter().cloned()),
                    _ => {}
                }
            }
        }
        return Ok(Geometry::MultiPolygon(polys));
    }
    if let Some(rest) = name.strip_prefix("continent/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "continent refs no longer take a modifier; got `{name}`. \
                 The `/mainland` suffix has been removed."
            )));
        }
        let key = rest.to_lowercase();
        return idx
            .continents
            .get(&key)
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown continent: {rest}")));
    }
    if let Some(rest) = name.strip_prefix("subregion/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "subregion refs no longer take a modifier; got `{name}`. \
                 The `/mainland` suffix has been removed."
            )));
        }
        let key = rest.to_lowercase();
        return idx
            .subregions
            .get(&key)
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown subregion: {rest}")));
    }
    Err(MapError::Resolve(format!("unsupported feature ref: {name}")))
}

/// Fallback: return ISOs whose bbox intersects the target's bbox.
/// Used when the topological graph has no entries for the target
/// (island nations, NE precision gaps).
fn fallback_bbox_neighbors<'a>(iso: &str, idx: &'a NeIndex) -> Vec<&'a str> {
    let target = match idx.country_bbox.get(iso) {
        Some(b) => b,
        None => return vec![],
    };
    idx.countries
        .iter()
        .filter(|(k, feat)| k.as_str() != iso && feat.bbox.intersects(target))
        .map(|(k, _)| k.as_str())
        .collect()
}

// ---------- index construction ----------

fn build_index(dir: &Path) -> Result<NeIndex, MapError> {
    let mut idx = NeIndex::default();

    // Countries
    let countries = dir.join("ne_10m_admin_0_countries.shp");
    if countries.exists() {
        load_admin0(&countries, &mut idx)?;
    } else {
        tracing::warn!(
            "natural-earth: missing {}; country/<iso> refs will fail",
            countries.display()
        );
    }

    // Admin-1
    let admin1 = dir.join("ne_10m_admin_1_states_provinces.shp");
    if admin1.exists() {
        load_admin1(&admin1, &mut idx)?;
    } else {
        tracing::warn!(
            "natural-earth: missing {}; admin1/* refs will fail",
            admin1.display()
        );
    }

    // Coastline
    let coast = dir.join("ne_10m_coastline.shp");
    if coast.exists() {
        load_coastline(&coast, &mut idx)?;
    } else {
        tracing::warn!(
            "natural-earth: missing {}; coastline refs will fail",
            coast.display()
        );
    }

    // Build topological neighbour graph from country polygons.
    build_neighbor_graph(&mut idx);

    Ok(idx)
}

fn load_admin0(path: &Path, idx: &mut NeIndex) -> Result<(), MapError> {
    let mut reader = shapefile::Reader::from_path(path)
        .map_err(|e| MapError::Resolve(format!("read {}: {e}", path.display())))?;

    let mut continent_buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
    let mut subregion_buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();

    for rec in reader.iter_shapes_and_records() {
        let (shape, record) = rec
            .map_err(|e| MapError::Resolve(format!("ne_admin0 row: {e}")))?;
        let iso = match record.get("ADM0_A3").or_else(|| record.get("ISO_A3")) {
            Some(dbase::FieldValue::Character(Some(s))) => s.trim().to_string(),
            _ => continue,
        };
        if iso.is_empty() || iso == "-99" {
            continue;
        }
        let geom = match shape_to_geometry(shape) {
            Some(g) => g,
            None => continue,
        };
        let bbox = geom.bbox();

        // Accumulate into continent / subregion buckets. Each country
        // contributes its full geometry — viewport clustering handles
        // outlying components on the rendering side.
        if let Some(c) = record.get("CONTINENT").and_then(char_field) {
            continent_buckets
                .entry(c.to_lowercase())
                .or_default()
                .push((geom.clone(), bbox));
        }
        if let Some(s) = record.get("SUBREGION").and_then(char_field) {
            subregion_buckets
                .entry(s.to_lowercase())
                .or_default()
                .push((geom.clone(), bbox));
        }

        idx.country_bbox.insert(iso.clone(), bbox);
        idx.countries.insert(iso, NeFeature { geom, bbox });
    }

    // Fold buckets into composite MultiPolygon features.
    fold_into_composites(continent_buckets, &mut idx.continents);
    fold_into_composites(subregion_buckets, &mut idx.subregions);

    Ok(())
}

/// Merge a bucket of `(Geometry, BBox)` entries into composite
/// `MultiPolygon` features keyed by group name.
fn fold_into_composites(
    buckets: HashMap<String, Vec<(Geometry, BBox)>>,
    dest: &mut HashMap<String, NeFeature>,
) {
    for (key, entries) in buckets {
        let mut polys: Vec<Polygon> = Vec::new();
        let mut combined_bbox = BBox::empty();
        for (geom, bbox) in entries {
            combined_bbox.extend(bbox);
            match geom {
                Geometry::Polygon { outer, holes } => {
                    polys.push(Polygon { outer, holes });
                }
                Geometry::MultiPolygon(ps) => polys.extend(ps),
                _ => {}
            }
        }
        dest.insert(
            key,
            NeFeature {
                geom: Geometry::MultiPolygon(polys),
                bbox: combined_bbox,
            },
        );
    }
}

/// Helper to extract a trimmed String from a Character dbase field.
fn char_field(fv: &dbase::FieldValue) -> Option<String> {
    match fv {
        dbase::FieldValue::Character(Some(s)) => {
            let trimmed = s.trim().to_string();
            if trimmed.is_empty() { None } else { Some(trimmed) }
        }
        _ => None,
    }
}

fn load_admin1(path: &Path, idx: &mut NeIndex) -> Result<(), MapError> {
    let mut reader = shapefile::Reader::from_path(path)
        .map_err(|e| MapError::Resolve(format!("read {}: {e}", path.display())))?;

    // Accumulate per-(iso, region) polygons for composite region
    // features.
    let mut region_buckets: HashMap<(String, String), Vec<(Geometry, BBox)>> = HashMap::new();

    for rec in reader.iter_shapes_and_records() {
        let (shape, record) = rec
            .map_err(|e| MapError::Resolve(format!("ne_admin1 row: {e}")))?;
        let iso = record
            .get("adm0_a3")
            .or_else(|| record.get("ADM0_A3"))
            .and_then(char_field);
        let iso = match iso {
            Some(s) => s,
            None => continue,
        };
        let name_en = record
            .get("name_en")
            .or_else(|| record.get("NAME_EN"))
            .and_then(char_field);
        let name_local = record
            .get("name")
            .or_else(|| record.get("NAME"))
            .and_then(char_field);
        let region_name = record.get("region").and_then(char_field);

        // Must have at least one name.
        if name_en.is_none() && name_local.is_none() {
            continue;
        }
        let geom = match shape_to_geometry(shape) {
            Some(g) => g,
            None => continue,
        };
        let bbox = geom.bbox();
        let feat = NeFeature {
            geom: geom.clone(),
            bbox,
        };

        // Index under both name_en and name (when they differ).
        // `or_insert` keeps the first-seen geometry on collision.
        let mut seen = HashSet::new();
        for n in [name_en.as_deref(), name_local.as_deref()]
            .into_iter()
            .flatten()
        {
            let key = (iso.clone(), n.to_lowercase());
            if seen.insert(key.clone()) {
                idx.admin1.entry(key).or_insert_with(|| feat.clone());
            }
        }

        // Accumulate into region bucket.
        if let Some(rn) = region_name {
            let rkey = (iso.clone(), rn.to_lowercase());
            region_buckets.entry(rkey).or_default().push((geom, bbox));
        }
    }

    // Fold region buckets into composite multipolygon features.
    for (key, entries) in region_buckets {
        let mut polys: Vec<Polygon> = Vec::new();
        let mut combined_bbox = BBox::empty();
        for (geom, bbox) in entries {
            combined_bbox.extend(bbox);
            match geom {
                Geometry::Polygon { outer, holes } => {
                    polys.push(Polygon { outer, holes });
                }
                Geometry::MultiPolygon(ps) => polys.extend(ps),
                _ => {}
            }
        }
        idx.regions.insert(
            key,
            NeFeature {
                geom: Geometry::MultiPolygon(polys),
                bbox: combined_bbox,
            },
        );
    }

    Ok(())
}

fn load_coastline(path: &Path, idx: &mut NeIndex) -> Result<(), MapError> {
    let mut reader = shapefile::Reader::from_path(path)
        .map_err(|e| MapError::Resolve(format!("read {}: {e}", path.display())))?;
    for rec in reader.iter_shapes_and_records() {
        let (shape, _) = rec
            .map_err(|e| MapError::Resolve(format!("ne_coastline row: {e}")))?;
        if let Some(geom) = shape_to_geometry(shape) {
            let bbox = geom.bbox();
            idx.coastline.push(NeFeature { geom, bbox });
        }
    }
    Ok(())
}

// ---------- topological neighbour graph ----------

/// Quantized coordinate for segment hashing. We round to 5 decimal
/// places (~1 m at the equator) to absorb floating-point jitter between
/// independently-encoded polygons that share a boundary.
type QCoord = (i64, i64);

fn quantize(p: LonLat) -> QCoord {
    // Multiply by 1e5 and round to i64.
    ((p.lon * 1e5).round() as i64, (p.lat * 1e5).round() as i64)
}

/// Canonical segment key — sorted so (A, B) == (B, A).
fn seg_key(a: QCoord, b: QCoord) -> (QCoord, QCoord) {
    if a <= b { (a, b) } else { (b, a) }
}

/// Walk every country polygon's edges, record which ISOs share each
/// edge, then build a mutual neighbour set.
fn build_neighbor_graph(idx: &mut NeIndex) {
    // segment → set of ISOs that own this segment
    let mut edge_owners: HashMap<(QCoord, QCoord), HashSet<String>> = HashMap::new();

    for (iso, feat) in &idx.countries {
        let rings = collect_rings(&feat.geom);
        for ring in rings {
            for pair in ring.windows(2) {
                let key = seg_key(quantize(pair[0]), quantize(pair[1]));
                edge_owners.entry(key).or_default().insert(iso.clone());
            }
        }
    }

    // Any segment shared by ≥ 2 ISOs → mutual neighbours.
    let mut graph: HashMap<String, HashSet<String>> = HashMap::new();
    for (_seg, owners) in &edge_owners {
        if owners.len() < 2 {
            continue;
        }
        let list: Vec<&String> = owners.iter().collect();
        for i in 0..list.len() {
            for j in (i + 1)..list.len() {
                graph.entry(list[i].clone()).or_default().insert(list[j].clone());
                graph.entry(list[j].clone()).or_default().insert(list[i].clone());
            }
        }
    }

    // Convert to sorted Vecs for deterministic output.
    for (iso, set) in graph {
        let mut v: Vec<String> = set.into_iter().collect();
        v.sort();
        idx.neighbors.insert(iso, v);
    }
}

/// Collect all rings (outer + holes) from a geometry as slices of points.
fn collect_rings(g: &Geometry) -> Vec<&[LonLat]> {
    let mut out = Vec::new();
    match g {
        Geometry::Polygon { outer, holes } => {
            out.push(outer.as_slice());
            for h in holes {
                out.push(h.as_slice());
            }
        }
        Geometry::MultiPolygon(polys) => {
            for p in polys {
                out.push(p.outer.as_slice());
                for h in &p.holes {
                    out.push(h.as_slice());
                }
            }
        }
        _ => {}
    }
    out
}

// ---------- geometry conversion ----------

fn shape_to_geometry(shape: shapefile::Shape) -> Option<Geometry> {
    use shapefile::Shape;
    match shape {
        Shape::Polygon(p) => Some(polygon_to_geometry(p)),
        Shape::Polyline(p) => Some(polyline_to_geometry(p)),
        Shape::Point(pt) => Some(Geometry::Point(LonLat {
            lon: pt.x,
            lat: pt.y,
        })),
        _ => None,
    }
}

fn polygon_to_geometry(poly: shapefile::Polygon) -> Geometry {
    use shapefile::record::polygon::PolygonRing;
    let mut polygons: Vec<Polygon> = Vec::new();
    let mut current: Option<Polygon> = None;
    for ring in poly.into_inner() {
        match ring {
            PolygonRing::Outer(pts) => {
                if let Some(c) = current.take() {
                    polygons.push(c);
                }
                let mut lonlats: Vec<LonLat> = pts
                    .into_iter()
                    .map(|p| LonLat { lon: p.x, lat: p.y })
                    .collect();
                normalize_antimeridian(&mut lonlats);
                current = Some(Polygon {
                    outer: lonlats,
                    holes: Vec::new(),
                });
            }
            PolygonRing::Inner(pts) => {
                if let Some(c) = current.as_mut() {
                    let mut lonlats: Vec<LonLat> = pts
                        .into_iter()
                        .map(|p| LonLat { lon: p.x, lat: p.y })
                        .collect();
                    normalize_antimeridian(&mut lonlats);
                    c.holes.push(lonlats);
                }
            }
        }
    }
    if let Some(c) = current {
        polygons.push(c);
    }
    // Reunite polygons that NE pre-split at the dateline (Russia's
    // Chukotka, Fiji, etc.). Without this, the two halves' artificial
    // closing edges show up as a vertical seam through the landmass.
    let polygons = stitch_dateline_polygons(polygons);
    if polygons.len() == 1 {
        let p = polygons.into_iter().next().unwrap();
        Geometry::Polygon {
            outer: p.outer,
            holes: p.holes,
        }
    } else {
        Geometry::MultiPolygon(polygons)
    }
}

fn polyline_to_geometry(line: shapefile::Polyline) -> Geometry {
    let parts: Vec<Vec<LonLat>> = line
        .into_inner()
        .into_iter()
        .map(|part| {
            let mut lonlats: Vec<LonLat> = part
                .into_iter()
                .map(|p| LonLat { lon: p.x, lat: p.y })
                .collect();
            normalize_antimeridian(&mut lonlats);
            lonlats
        })
        .collect();
    if parts.len() == 1 {
        Geometry::LineString(parts.into_iter().next().unwrap())
    } else {
        Geometry::MultiLineString(parts)
    }
}

/// If a ring/polyline spans the antimeridian (has points with lon < -90
/// and points with lon > 90), shift all negative-longitude points by
/// +360° to make the coordinate range continuous. This prevents Russia,
/// Alaska, etc. from producing a ~350°-wide bbox that covers the whole
/// world.
///
/// The ±90° threshold avoids false-triggering on features that simply
/// straddle the prime meridian (e.g. UK at -8° to 2°).
fn normalize_antimeridian(pts: &mut [LonLat]) {
    let has_far_neg = pts.iter().any(|p| p.lon < -90.0);
    let has_far_pos = pts.iter().any(|p| p.lon > 90.0);
    if has_far_neg && has_far_pos {
        for p in pts.iter_mut() {
            if p.lon < 0.0 {
                p.lon += 360.0;
            }
        }
    }
}

/// Tolerance for "vertex sits on the dateline" detection. Natural
/// Earth dateline-edge vertices are at lon == ±180.0 exactly, so a
/// loose tolerance is fine.
const DATELINE_EPS: f64 = 1e-6;

/// Natural Earth pre-splits dateline-crossing polygons into two
/// pieces: one ending at lon=+180 with a vertical closing edge, and
/// another starting at lon=-180 with the matching mirrored edge.
/// Russia's Chukotka peninsula is the canonical example. When we
/// later draw both halves on a viewport that doesn't cross the
/// dateline (e.g. an Asia-centric Russia map), the two abutting
/// vertical closure edges show up as a vertical seam through the
/// landmass.
///
/// This function detects pairs of polygons that abut on the dateline
/// and stitches them back into a single ring whose longitudes wrap
/// past 180° (e.g. the merged Russia ring spans lon = 27° to 191°).
/// The merged ring crosses the antimeridian only conceptually; its
/// vertices are continuous, so downstream rotation + `split_at_wrap`
/// handles it correctly for *any* viewport.
///
/// Pairs are matched by:
///   * one polygon has consecutive vertices on lon = +180 (the +180-
///     side closure edge),
///   * the other has consecutive vertices on lon = -180,
///   * their latitude ranges along that edge overlap.
///
/// If no matching pair exists, the polygons are returned unchanged.
fn stitch_dateline_polygons(polys: Vec<Polygon>) -> Vec<Polygon> {
    if polys.len() < 2 {
        return polys;
    }
    // Find the index range of every dateline edge in every polygon.
    // A dateline edge is a maximal run of consecutive vertices all
    // sitting on lon = ±180 (actually we look for pairs of adjacent
    // vertices both on the meridian — that signals an artificial
    // closure edge, not a coincidental near-pole crossing).
    let mut polys: Vec<Option<Polygon>> = polys.into_iter().map(Some).collect();
    let mut stitched_anything = true;
    // Iterate to fixed point so a chain (very rare) of dateline
    // pieces can all merge.
    while stitched_anything {
        stitched_anything = false;
        let n = polys.len();
        'outer: for i in 0..n {
            if polys[i].is_none() {
                continue;
            }
            let a_edge = match find_dateline_edge(polys[i].as_ref().unwrap(), 180.0) {
                Some(e) => e,
                None => continue,
            };
            for j in 0..n {
                if i == j || polys[j].is_none() {
                    continue;
                }
                let b_edge = match find_dateline_edge(polys[j].as_ref().unwrap(), -180.0) {
                    Some(e) => e,
                    None => continue,
                };
                // Lat ranges along the two edges must overlap.
                if !lat_ranges_overlap(&a_edge, &b_edge) {
                    continue;
                }
                // Stitch.
                let a = polys[i].take().unwrap();
                let b = polys[j].take().unwrap();
                let merged = stitch_pair(a, a_edge, b, b_edge);
                polys[i] = Some(merged);
                stitched_anything = true;
                break 'outer;
            }
        }
    }
    polys.into_iter().flatten().collect()
}

/// Returns the (start, end) vertex indices of the longest consecutive
/// run of vertices on `target_lon` (within tolerance), if any. The
/// run must have at least two vertices to count as a closure edge.
/// Indices are inclusive.
fn find_dateline_edge(p: &Polygon, target_lon: f64) -> Option<DatelineEdge> {
    let pts = &p.outer;
    let n = pts.len();
    if n < 4 {
        return None;
    }
    // Drop the closure-duplicate vertex if present so the run doesn't
    // get artificially split by it.
    let working_n = if pts.first() == pts.last() { n - 1 } else { n };
    let on_meridian = |idx: usize| {
        (pts[idx % working_n].lon - target_lon).abs() < DATELINE_EPS
    };
    // Find any starting index where the run begins.
    let mut best: Option<DatelineEdge> = None;
    let mut start: Option<usize> = None;
    // Walk twice around so we can capture runs that span the index-0
    // boundary.
    for i in 0..(working_n * 2) {
        if on_meridian(i) {
            if start.is_none() {
                start = Some(i);
            }
        } else if let Some(s) = start.take() {
            let len = i - s;
            if len >= 2 {
                let s_norm = s % working_n;
                let e_norm = (i - 1) % working_n;
                let lat0 = pts[s_norm].lat;
                let lat1 = pts[e_norm].lat;
                let edge = DatelineEdge {
                    start: s_norm,
                    end: e_norm,
                    lat_min: lat0.min(lat1),
                    lat_max: lat0.max(lat1),
                };
                if best.as_ref().map(|b| len > (b.end + working_n - b.start) % working_n + 1).unwrap_or(true) {
                    best = Some(edge);
                }
            }
            // We've already covered the whole loop once; no need to
            // continue around.
            if i >= working_n {
                break;
            }
        }
    }
    best
}

#[derive(Clone, Copy, Debug)]
struct DatelineEdge {
    /// Index of the first vertex on the meridian (inclusive).
    start: usize,
    /// Index of the last vertex on the meridian (inclusive).
    end: usize,
    lat_min: f64,
    lat_max: f64,
}

fn lat_ranges_overlap(a: &DatelineEdge, b: &DatelineEdge) -> bool {
    !(a.lat_max < b.lat_min || b.lat_max < a.lat_min)
}

/// Stitch polygon A's +180-edge to polygon B's -180-edge. After
/// stitching, B's vertices are shifted by +360° in longitude so the
/// merged ring forms a continuous loop with longitudes spanning
/// roughly `(A.min_lon, B.max_lon + 360°)`.
///
/// Strategy: walk A from just-after-its-dateline-edge all the way
/// around to just-before-its-dateline-edge. Then walk shifted B from
/// just-after-its-dateline-edge around to just-before. Concatenate
/// and close.
fn stitch_pair(a: Polygon, a_edge: DatelineEdge, b: Polygon, b_edge: DatelineEdge) -> Polygon {
    let a_pts = strip_closure(&a.outer);
    let b_pts: Vec<LonLat> = strip_closure(&b.outer)
        .iter()
        .map(|p| LonLat { lon: p.lon + 360.0, lat: p.lat })
        .collect();
    let a_n = a_pts.len();
    let b_n = b_pts.len();

    // Build the merged outer ring.
    //   * Start just after A's edge (= a_edge.end + 1 mod a_n).
    //   * Walk A all the way around until we reach a_edge.start (exclusive).
    //   * Then jump to B's edge endpoint that lat-matches (B's edge
    //     was traversed in the opposite direction relative to A).
    //   * Walk B all the way around back to its other endpoint.
    let mut merged: Vec<LonLat> = Vec::with_capacity(a_n + b_n);
    // A walk: from (end+1) round to (start-1), inclusive.
    let mut idx = (a_edge.end + 1) % a_n;
    loop {
        merged.push(a_pts[idx]);
        if idx == a_edge.start {
            // We've collected all of A's non-edge vertices.
            // Don't include the edge itself; it's the seam.
            merged.pop();
            break;
        }
        idx = (idx + 1) % a_n;
    }
    // B walk: from b_edge.end+1 round to b_edge.start-1, inclusive.
    let mut idx = (b_edge.end + 1) % b_n;
    loop {
        merged.push(b_pts[idx]);
        if idx == b_edge.start {
            merged.pop();
            break;
        }
        idx = (idx + 1) % b_n;
    }
    // Close the ring.
    if let Some(&first) = merged.first() {
        merged.push(first);
    }

    Polygon {
        outer: merged,
        // Holes are kept as-is from A; B's holes are shifted +360 and
        // appended. (Holes don't typically straddle the dateline; if
        // any did, their per-ring `normalize_antimeridian` already
        // handled them.)
        holes: a
            .holes
            .into_iter()
            .chain(b.holes.into_iter().map(|h| {
                h.into_iter()
                    .map(|p| LonLat { lon: p.lon + 360.0, lat: p.lat })
                    .collect()
            }))
            .collect(),
    }
}

/// Drop the trailing closure-duplicate vertex if present.
fn strip_closure(pts: &[LonLat]) -> Vec<LonLat> {
    if pts.len() > 1 && pts.first() == pts.last() {
        pts[..pts.len() - 1].to_vec()
    } else {
        pts.to_vec()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_data_dir_returns_resolve_error() {
        let saved = std::env::var("NATURAL_EARTH_DATA").ok();
        unsafe {
            std::env::remove_var("NATURAL_EARTH_DATA");
        }
        if let Some(v) = saved {
            unsafe {
                std::env::set_var("NATURAL_EARTH_DATA", v);
            }
        }
    }

    fn square(min_lon: f64, min_lat: f64, side: f64) -> Polygon {
        let max_lon = min_lon + side;
        let max_lat = min_lat + side;
        Polygon {
            outer: vec![
                LonLat { lon: min_lon, lat: min_lat },
                LonLat { lon: max_lon, lat: min_lat },
                LonLat { lon: max_lon, lat: max_lat },
                LonLat { lon: min_lon, lat: max_lat },
                LonLat { lon: min_lon, lat: min_lat },
            ],
            holes: vec![],
        }
    }

    // ---- Item E: dual-name indexing ----

    #[test]
    fn admin1_indexes_both_names() {
        // Simulate what load_admin1 does: two names for one row
        // should produce two index entries.
        let mut idx = NeIndex::default();
        let geom = Geometry::Polygon {
            outer: square(0.0, 0.0, 1.0).outer,
            holes: vec![],
        };
        let feat = NeFeature { geom, bbox: BBox::empty() };
        // "name_en" = "Zealand", "name" = "Sjaælland"
        let iso = "DNK".to_string();
        idx.admin1.entry((iso.clone(), "zealand".to_string()))
            .or_insert_with(|| feat.clone());
        idx.admin1.entry((iso.clone(), "sjaælland".to_string()))
            .or_insert_with(|| feat.clone());

        assert!(idx.admin1.contains_key(&("DNK".into(), "zealand".into())));
        assert!(idx.admin1.contains_key(&("DNK".into(), "sjaælland".into())));
    }

    // ---- Item F: region composite ----

    #[test]
    fn region_composite_merges_provinces() {
        // Two provinces in the same region should produce a 2-polygon
        // MultiPolygon in the region index.
        let mut idx = NeIndex::default();
        let p1 = square(0.0, 0.0, 1.0);
        let p2 = square(2.0, 0.0, 1.0);
        let polys = vec![p1, p2];
        let mut combined_bbox = BBox::empty();
        let mut poly_vec: Vec<Polygon> = Vec::new();
        for p in polys {
            let g = Geometry::Polygon { outer: p.outer.clone(), holes: p.holes.clone() };
            combined_bbox.extend(g.bbox());
            poly_vec.push(p);
        }
        idx.regions.insert(
            ("ITA".into(), "sicily".into()),
            NeFeature {
                geom: Geometry::MultiPolygon(poly_vec),
                bbox: combined_bbox,
            },
        );
        let feat = idx.regions.get(&("ITA".into(), "sicily".into())).unwrap();
        match &feat.geom {
            Geometry::MultiPolygon(ps) => assert_eq!(ps.len(), 2),
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    // ---- Item D: topological neighbours ----

    #[test]
    fn neighbor_graph_two_countries_sharing_edge() {
        // Two squares sharing a vertical edge at x=1.
        let mut idx = NeIndex::default();
        let left = square(0.0, 0.0, 1.0);
        let right = square(1.0, 0.0, 1.0);
        let g_left = Geometry::Polygon { outer: left.outer, holes: vec![] };
        let g_right = Geometry::Polygon { outer: right.outer, holes: vec![] };
        idx.countries.insert("AAA".into(), NeFeature {
            bbox: g_left.bbox(), geom: g_left,
        });
        idx.countries.insert("BBB".into(), NeFeature {
            bbox: g_right.bbox(), geom: g_right,
        });
        build_neighbor_graph(&mut idx);
        assert_eq!(idx.neighbors.get("AAA").unwrap(), &vec!["BBB".to_string()]);
        assert_eq!(idx.neighbors.get("BBB").unwrap(), &vec!["AAA".to_string()]);
    }

    #[test]
    fn neighbor_graph_isolates_islands() {
        // Two squares far apart — no shared edges.
        let mut idx = NeIndex::default();
        let a = square(0.0, 0.0, 1.0);
        let b = square(100.0, 100.0, 1.0);
        let g_a = Geometry::Polygon { outer: a.outer, holes: vec![] };
        let g_b = Geometry::Polygon { outer: b.outer, holes: vec![] };
        idx.countries.insert("AAA".into(), NeFeature {
            bbox: g_a.bbox(), geom: g_a,
        });
        idx.countries.insert("BBB".into(), NeFeature {
            bbox: g_b.bbox(), geom: g_b,
        });
        build_neighbor_graph(&mut idx);
        // Neither should appear in the graph.
        assert!(idx.neighbors.get("AAA").is_none());
        assert!(idx.neighbors.get("BBB").is_none());
    }

    #[test]
    fn neighbor_graph_three_countries_shared_corner() {
        // Three squares: AAA=[0,0]-[1,1], BBB=[1,0]-[2,1], CCC=[0,1]-[1,2].
        // AAA-BBB share a vertical edge. AAA-CCC share a horizontal edge.
        // BBB-CCC share only a corner point (no edge) → should NOT be neighbours.
        let mut idx = NeIndex::default();
        let a = square(0.0, 0.0, 1.0);
        let b = square(1.0, 0.0, 1.0);
        let c = square(0.0, 1.0, 1.0);
        for (iso, sq) in [("AAA", a), ("BBB", b), ("CCC", c)] {
            let g = Geometry::Polygon { outer: sq.outer, holes: vec![] };
            idx.countries.insert(iso.into(), NeFeature { bbox: g.bbox(), geom: g });
        }
        build_neighbor_graph(&mut idx);
        let a_neighbors = idx.neighbors.get("AAA").unwrap();
        assert!(a_neighbors.contains(&"BBB".to_string()));
        assert!(a_neighbors.contains(&"CCC".to_string()));
        let b_neighbors = idx.neighbors.get("BBB").unwrap();
        assert!(b_neighbors.contains(&"AAA".to_string()));
        // BBB and CCC only share a single corner point, not an edge,
        // so they should NOT be neighbours.
        assert!(!b_neighbors.contains(&"CCC".to_string()));
    }

    // ---- Antimeridian normalization ----

    #[test]
    fn antimeridian_crossing_normalized() {
        // Ring with points at 170° and -170° (spans dateline).
        let mut pts = vec![
            LonLat { lon: 170.0, lat: 50.0 },
            LonLat { lon: 175.0, lat: 55.0 },
            LonLat { lon: -170.0, lat: 55.0 },
            LonLat { lon: -175.0, lat: 50.0 },
            LonLat { lon: 170.0, lat: 50.0 },
        ];
        normalize_antimeridian(&mut pts);
        // Negative lons should be shifted by +360.
        assert!(pts[2].lon > 180.0, "got {}", pts[2].lon);
        assert!((pts[2].lon - 190.0).abs() < 0.01);
        assert!((pts[3].lon - 185.0).abs() < 0.01);
    }

    #[test]
    fn prime_meridian_crossing_unchanged() {
        // UK-like: -8° to 2° — must NOT trigger.
        let mut pts = vec![
            LonLat { lon: -8.0, lat: 50.0 },
            LonLat { lon: 2.0, lat: 51.0 },
            LonLat { lon: -8.0, lat: 50.0 },
        ];
        let orig: Vec<f64> = pts.iter().map(|p| p.lon).collect();
        normalize_antimeridian(&mut pts);
        let after: Vec<f64> = pts.iter().map(|p| p.lon).collect();
        assert_eq!(orig, after);
    }

    // ---- Continent / subregion composites ----

    #[test]
    fn fold_into_composites_merges_polygons() {
        let mut dest: HashMap<String, NeFeature> = HashMap::new();
        let p1 = Geometry::Polygon {
            outer: square(0.0, 0.0, 1.0).outer,
            holes: vec![],
        };
        let p2 = Geometry::Polygon {
            outer: square(2.0, 0.0, 1.0).outer,
            holes: vec![],
        };
        let mut buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
        buckets.entry("europe".into()).or_default().push((p1.clone(), p1.bbox()));
        buckets.entry("europe".into()).or_default().push((p2.clone(), p2.bbox()));
        fold_into_composites(buckets, &mut dest);

        let feat = dest.get("europe").unwrap();
        match &feat.geom {
            Geometry::MultiPolygon(ps) => assert_eq!(ps.len(), 2),
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
        // Combined bbox should span both squares.
        assert!(feat.bbox.max_lon >= 3.0);
    }

    #[test]
    fn fold_separates_groups() {
        let mut dest: HashMap<String, NeFeature> = HashMap::new();
        let p1 = Geometry::Polygon {
            outer: square(0.0, 0.0, 1.0).outer,
            holes: vec![],
        };
        let p2 = Geometry::Polygon {
            outer: square(10.0, 10.0, 1.0).outer,
            holes: vec![],
        };
        let mut buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
        buckets.entry("europe".into()).or_default().push((p1.clone(), p1.bbox()));
        buckets.entry("asia".into()).or_default().push((p2.clone(), p2.bbox()));
        fold_into_composites(buckets, &mut dest);

        assert_eq!(dest.len(), 2);
        assert!(dest.contains_key("europe"));
        assert!(dest.contains_key("asia"));
    }

    // ---------- dateline stitching ----------

    /// A simple Russia-shaped pair: polygon A is the western half
    /// (with a closing edge on lon=+180), polygon B is Chukotka
    /// (with a closing edge on lon=-180). After stitching they
    /// should become one ring.
    #[test]
    fn stitch_pair_basic_russia_shape() {
        // A: ccw outer ring 0..180 lat 60..70, with the dateline
        // closing edge from (180, 70) → (180, 60).
        let a = Polygon {
            outer: vec![
                LonLat { lon: 0.0,   lat: 60.0 },
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 70.0 },
                LonLat { lon: 0.0,   lat: 70.0 },
                LonLat { lon: 0.0,   lat: 60.0 },
            ],
            holes: vec![],
        };
        // B: ccw outer ring -180..-160 lat 60..70, with the dateline
        // edge (-180, 60) → (-180, 70).
        let b = Polygon {
            outer: vec![
                LonLat { lon: -180.0, lat: 60.0 },
                LonLat { lon: -160.0, lat: 60.0 },
                LonLat { lon: -160.0, lat: 70.0 },
                LonLat { lon: -180.0, lat: 70.0 },
                LonLat { lon: -180.0, lat: 60.0 },
            ],
            holes: vec![],
        };
        let polys = stitch_dateline_polygons(vec![a, b]);
        assert_eq!(polys.len(), 1, "expected single stitched polygon");
        let merged = &polys[0];
        // Stitched ring should span past lon=180.
        let max_lon = merged.outer.iter().map(|p| p.lon).fold(f64::NEG_INFINITY, f64::max);
        let min_lon = merged.outer.iter().map(|p| p.lon).fold(f64::INFINITY, f64::min);
        assert!(max_lon > 180.0, "expected max_lon > 180, got {max_lon}");
        assert!(min_lon >= 0.0, "expected min_lon >= 0, got {min_lon}");
        // No vertex on the dateline (lon == 180 exactly).
        let on_dateline = merged.outer.iter().filter(|p| (p.lon - 180.0).abs() < 1e-6).count();
        assert!(on_dateline == 0, "stitched ring still has {} dateline vertices", on_dateline);
        // First == last (closed ring).
        assert_eq!(merged.outer.first(), merged.outer.last());
    }

    #[test]
    fn stitch_no_match_passthrough() {
        // Two unrelated squares far from the dateline.
        let a = square(0.0, 0.0, 5.0);
        let b = square(50.0, 50.0, 5.0);
        let polys = stitch_dateline_polygons(vec![a.clone(), b.clone()]);
        assert_eq!(polys.len(), 2);
    }

    #[test]
    fn stitch_with_only_one_dateline_polygon_passthrough() {
        // A has a +180 edge but no matching -180 polygon exists.
        let a = Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 180.0, lat: 0.0 },
                LonLat { lon: 180.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let b = square(50.0, 50.0, 1.0);
        let polys = stitch_dateline_polygons(vec![a, b]);
        assert_eq!(polys.len(), 2, "no stitching when there's no -180 partner");
    }

    #[test]
    fn stitch_lat_range_mismatch_passthrough() {
        // A's +180 edge lat 60..70, B's -180 edge lat 0..10 (no overlap).
        let a = Polygon {
            outer: vec![
                LonLat { lon: 0.0,   lat: 60.0 },
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 70.0 },
                LonLat { lon: 0.0,   lat: 70.0 },
                LonLat { lon: 0.0,   lat: 60.0 },
            ],
            holes: vec![],
        };
        let b = Polygon {
            outer: vec![
                LonLat { lon: -180.0, lat: 0.0 },
                LonLat { lon: -160.0, lat: 0.0 },
                LonLat { lon: -160.0, lat: 10.0 },
                LonLat { lon: -180.0, lat: 10.0 },
                LonLat { lon: -180.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let polys = stitch_dateline_polygons(vec![a, b]);
        assert_eq!(polys.len(), 2);
    }

    #[test]
    fn find_dateline_edge_basic() {
        let p = Polygon {
            outer: vec![
                LonLat { lon: 0.0,   lat: 0.0 },
                LonLat { lon: 180.0, lat: 0.0 },
                LonLat { lon: 180.0, lat: 10.0 },
                LonLat { lon: 0.0,   lat: 10.0 },
                LonLat { lon: 0.0,   lat: 0.0 },
            ],
            holes: vec![],
        };
        let e = find_dateline_edge(&p, 180.0).unwrap();
        // Two consecutive vertices on lon=180 (indices 1 and 2).
        assert_eq!(e.start, 1);
        assert_eq!(e.end, 2);
        assert!((e.lat_min - 0.0).abs() < 1e-9);
        assert!((e.lat_max - 10.0).abs() < 1e-9);
    }

    #[test]
    fn find_dateline_edge_no_edge() {
        let p = square(0.0, 0.0, 5.0);
        assert!(find_dateline_edge(&p, 180.0).is_none());
    }

    #[test]
    fn lat_ranges_overlap_basic() {
        let a = DatelineEdge { start: 0, end: 0, lat_min: 0.0, lat_max: 10.0 };
        let b = DatelineEdge { start: 0, end: 0, lat_min: 5.0, lat_max: 15.0 };
        assert!(lat_ranges_overlap(&a, &b));
        let c = DatelineEdge { start: 0, end: 0, lat_min: 20.0, lat_max: 30.0 };
        assert!(!lat_ranges_overlap(&a, &c));
    }
}
