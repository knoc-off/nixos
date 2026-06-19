//! Shared geometry helpers used by every offline vector source
//! (`geoboundaries`, `natural_earth`).
//!
//! These are source-agnostic: they operate on the internal
//! [`Geometry`] / [`Polygon`] types after a loader has decoded a raw
//! record. Antimeridian normalization, dateline re-stitching, composite
//! folding and the topological neighbour graph all live here so the
//! per-source loaders stay thin.

use crate::geometry::{BBox, Geometry, LonLat, Polygon};
use std::collections::{HashMap, HashSet};

/// One indexed feature: a decoded geometry plus its cached bbox.
#[derive(Clone)]
pub struct Feature {
    pub geom: Geometry,
    pub bbox: BBox,
}

impl Feature {
    pub fn new(geom: Geometry) -> Self {
        let bbox = geom.bbox();
        Feature { geom, bbox }
    }
}

// ---------- antimeridian normalization ----------

/// If a ring/polyline spans the antimeridian (has points with lon < -90
/// and points with lon > 90), shift all negative-longitude points by
/// +360° to make the coordinate range continuous. This prevents Russia,
/// Alaska, etc. from producing a ~350°-wide bbox that covers the whole
/// world.
///
/// The ±90° threshold avoids false-triggering on features that simply
/// straddle the prime meridian (e.g. UK at -8° to 2°).
pub fn normalize_antimeridian(pts: &mut [LonLat]) {
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

// ---------- composite folding ----------

/// Merge a bucket of `(Geometry, BBox)` entries into composite
/// `MultiPolygon` [`Feature`]s keyed by group name.
pub fn fold_into_composites(
    buckets: HashMap<String, Vec<(Geometry, BBox)>>,
    dest: &mut HashMap<String, Feature>,
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
            Feature {
                geom: Geometry::MultiPolygon(polys),
                bbox: combined_bbox,
            },
        );
    }
}

// ---------- topological neighbour graph ----------

/// Quantized coordinate for segment hashing. We round to 5 decimal
/// places (~1 m at the equator) to absorb floating-point jitter between
/// independently-encoded polygons that share a boundary.
type QCoord = (i64, i64);

fn quantize(p: LonLat) -> QCoord {
    ((p.lon * 1e5).round() as i64, (p.lat * 1e5).round() as i64)
}

/// Canonical segment key — sorted so (A, B) == (B, A).
fn seg_key(a: QCoord, b: QCoord) -> (QCoord, QCoord) {
    if a <= b { (a, b) } else { (b, a) }
}

/// Walk every country polygon's edges, record which ISOs share each
/// edge, then build a mutual neighbour map: ISO → sorted neighbour ISOs.
pub fn build_neighbor_graph<'a, I>(countries: I) -> HashMap<String, Vec<String>>
where
    I: IntoIterator<Item = (&'a String, &'a Geometry)>,
{
    // segment → set of ISOs that own this segment
    let mut edge_owners: HashMap<(QCoord, QCoord), HashSet<String>> = HashMap::new();

    for (iso, geom) in countries {
        for ring in collect_rings(geom) {
            for pair in ring.windows(2) {
                let key = seg_key(quantize(pair[0]), quantize(pair[1]));
                edge_owners.entry(key).or_default().insert(iso.clone());
            }
        }
    }

    // Any segment shared by ≥ 2 ISOs → mutual neighbours.
    let mut graph: HashMap<String, HashSet<String>> = HashMap::new();
    for owners in edge_owners.values() {
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
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for (iso, set) in graph {
        let mut v: Vec<String> = set.into_iter().collect();
        v.sort();
        out.insert(iso, v);
    }
    out
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

// ---------- dateline stitching ----------

/// Tolerance for "vertex sits on the dateline" detection. Dateline-edge
/// vertices are at lon == ±180.0 exactly, so a loose tolerance is fine.
const DATELINE_EPS: f64 = 1e-6;

/// Some sources pre-split dateline-crossing polygons into two pieces:
/// one ending at lon=+180 with a vertical closing edge, and another
/// starting at lon=-180 with the matching mirrored edge. Russia's
/// Chukotka peninsula is the canonical example. When we later draw both
/// halves on a viewport that doesn't cross the dateline (e.g. an
/// Asia-centric Russia map), the two abutting vertical closure edges
/// show up as a vertical seam through the landmass.
///
/// This function detects pairs of polygons that abut on the dateline
/// and stitches them back into a single ring whose longitudes wrap past
/// 180° (e.g. the merged Russia ring spans lon = 27° to 191°). The
/// merged ring crosses the antimeridian only conceptually; its vertices
/// are continuous, so downstream rotation + `split_at_wrap` handles it
/// correctly for *any* viewport.
///
/// If no matching pair exists, the polygons are returned unchanged.
pub fn stitch_dateline_polygons(polys: Vec<Polygon>) -> Vec<Polygon> {
    if polys.len() < 2 {
        return polys;
    }
    let mut polys: Vec<Option<Polygon>> = polys.into_iter().map(Some).collect();
    let mut stitched_anything = true;
    // Iterate to fixed point so a chain (very rare) of dateline pieces
    // can all merge.
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
                if !lat_ranges_overlap(&a_edge, &b_edge) {
                    continue;
                }
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
/// run of vertices on `target_lon` (within tolerance), if any. The run
/// must have at least two vertices to count as a closure edge. Indices
/// are inclusive.
fn find_dateline_edge(p: &Polygon, target_lon: f64) -> Option<DatelineEdge> {
    let pts = &p.outer;
    let n = pts.len();
    if n < 4 {
        return None;
    }
    let working_n = if pts.first() == pts.last() { n - 1 } else { n };
    let on_meridian = |idx: usize| (pts[idx % working_n].lon - target_lon).abs() < DATELINE_EPS;
    let mut best: Option<DatelineEdge> = None;
    let mut start: Option<usize> = None;
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
                if best
                    .as_ref()
                    .map(|b| len > (b.end + working_n - b.start) % working_n + 1)
                    .unwrap_or(true)
                {
                    best = Some(edge);
                }
            }
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
/// merged ring forms a continuous loop with longitudes spanning roughly
/// `(A.min_lon, B.max_lon + 360°)`.
fn stitch_pair(a: Polygon, a_edge: DatelineEdge, b: Polygon, b_edge: DatelineEdge) -> Polygon {
    let a_pts = strip_closure(&a.outer);
    let b_pts: Vec<LonLat> = strip_closure(&b.outer)
        .iter()
        .map(|p| LonLat { lon: p.lon + 360.0, lat: p.lat })
        .collect();
    let a_n = a_pts.len();
    let b_n = b_pts.len();

    let mut merged: Vec<LonLat> = Vec::with_capacity(a_n + b_n);
    // A walk: from (end+1) round to (start-1), inclusive.
    let mut idx = (a_edge.end + 1) % a_n;
    loop {
        merged.push(a_pts[idx]);
        if idx == a_edge.start {
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
    if let Some(&first) = merged.first() {
        merged.push(first);
    }

    Polygon {
        outer: merged,
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

    #[test]
    fn antimeridian_crossing_normalized() {
        let mut pts = vec![
            LonLat { lon: 170.0, lat: 50.0 },
            LonLat { lon: 175.0, lat: 55.0 },
            LonLat { lon: -170.0, lat: 55.0 },
            LonLat { lon: -175.0, lat: 50.0 },
            LonLat { lon: 170.0, lat: 50.0 },
        ];
        normalize_antimeridian(&mut pts);
        assert!(pts[2].lon > 180.0, "got {}", pts[2].lon);
        assert!((pts[2].lon - 190.0).abs() < 0.01);
        assert!((pts[3].lon - 185.0).abs() < 0.01);
    }

    #[test]
    fn prime_meridian_crossing_unchanged() {
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

    #[test]
    fn fold_into_composites_merges_polygons() {
        let mut dest: HashMap<String, Feature> = HashMap::new();
        let p1 = Geometry::Polygon { outer: square(0.0, 0.0, 1.0).outer, holes: vec![] };
        let p2 = Geometry::Polygon { outer: square(2.0, 0.0, 1.0).outer, holes: vec![] };
        let mut buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
        buckets.entry("europe".into()).or_default().push((p1.clone(), p1.bbox()));
        buckets.entry("europe".into()).or_default().push((p2.clone(), p2.bbox()));
        fold_into_composites(buckets, &mut dest);

        let feat = dest.get("europe").unwrap();
        match &feat.geom {
            Geometry::MultiPolygon(ps) => assert_eq!(ps.len(), 2),
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
        assert!(feat.bbox.max_lon >= 3.0);
    }

    #[test]
    fn neighbor_graph_two_countries_sharing_edge() {
        let left = square(0.0, 0.0, 1.0);
        let right = square(1.0, 0.0, 1.0);
        let g_left = Geometry::Polygon { outer: left.outer, holes: vec![] };
        let g_right = Geometry::Polygon { outer: right.outer, holes: vec![] };
        let countries: Vec<(String, Geometry)> =
            vec![("AAA".into(), g_left), ("BBB".into(), g_right)];
        let graph = build_neighbor_graph(countries.iter().map(|(k, g)| (k, g)));
        assert_eq!(graph.get("AAA").unwrap(), &vec!["BBB".to_string()]);
        assert_eq!(graph.get("BBB").unwrap(), &vec!["AAA".to_string()]);
    }

    #[test]
    fn neighbor_graph_isolates_islands() {
        let a = square(0.0, 0.0, 1.0);
        let b = square(100.0, 100.0, 1.0);
        let g_a = Geometry::Polygon { outer: a.outer, holes: vec![] };
        let g_b = Geometry::Polygon { outer: b.outer, holes: vec![] };
        let countries: Vec<(String, Geometry)> = vec![("AAA".into(), g_a), ("BBB".into(), g_b)];
        let graph = build_neighbor_graph(countries.iter().map(|(k, g)| (k, g)));
        assert!(graph.get("AAA").is_none());
        assert!(graph.get("BBB").is_none());
    }

    #[test]
    fn neighbor_graph_three_countries_shared_corner() {
        let a = square(0.0, 0.0, 1.0);
        let b = square(1.0, 0.0, 1.0);
        let c = square(0.0, 1.0, 1.0);
        let countries: Vec<(String, Geometry)> = [("AAA", a), ("BBB", b), ("CCC", c)]
            .into_iter()
            .map(|(iso, sq)| (iso.to_string(), Geometry::Polygon { outer: sq.outer, holes: vec![] }))
            .collect();
        let graph = build_neighbor_graph(countries.iter().map(|(k, g)| (k, g)));
        let a_neighbors = graph.get("AAA").unwrap();
        assert!(a_neighbors.contains(&"BBB".to_string()));
        assert!(a_neighbors.contains(&"CCC".to_string()));
        let b_neighbors = graph.get("BBB").unwrap();
        assert!(b_neighbors.contains(&"AAA".to_string()));
        // BBB and CCC only share a single corner point, not an edge.
        assert!(!b_neighbors.contains(&"CCC".to_string()));
    }

    #[test]
    fn stitch_pair_basic_russia_shape() {
        let a = Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 70.0 },
                LonLat { lon: 0.0, lat: 70.0 },
                LonLat { lon: 0.0, lat: 60.0 },
            ],
            holes: vec![],
        };
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
        let max_lon = merged.outer.iter().map(|p| p.lon).fold(f64::NEG_INFINITY, f64::max);
        let min_lon = merged.outer.iter().map(|p| p.lon).fold(f64::INFINITY, f64::min);
        assert!(max_lon > 180.0, "expected max_lon > 180, got {max_lon}");
        assert!(min_lon >= 0.0, "expected min_lon >= 0, got {min_lon}");
        let on_dateline = merged.outer.iter().filter(|p| (p.lon - 180.0).abs() < 1e-6).count();
        assert!(on_dateline == 0, "stitched ring still has {on_dateline} dateline vertices");
        assert_eq!(merged.outer.first(), merged.outer.last());
    }

    #[test]
    fn stitch_no_match_passthrough() {
        let a = square(0.0, 0.0, 5.0);
        let b = square(50.0, 50.0, 5.0);
        let polys = stitch_dateline_polygons(vec![a.clone(), b.clone()]);
        assert_eq!(polys.len(), 2);
    }

    #[test]
    fn stitch_lat_range_mismatch_passthrough() {
        let a = Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: 180.0, lat: 70.0 },
                LonLat { lon: 0.0, lat: 70.0 },
                LonLat { lon: 0.0, lat: 60.0 },
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
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 180.0, lat: 0.0 },
                LonLat { lon: 180.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let e = find_dateline_edge(&p, 180.0).unwrap();
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
