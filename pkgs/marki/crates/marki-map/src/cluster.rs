//! Main-cluster viewport computation.
//!
//! ## Why
//!
//! Many countries have outlying components: the USA has Alaska + Hawaii
//! + Aleutians + Pacific territories; France has Corsica + Guiana +
//! Réunion + Mayotte; New Zealand has Chatham Islands. Europe has
//! Svalbard, Iceland, the Azores, etc. A naive union-of-bboxes
//! viewport zooms out so far that the "main" landmass is a tiny dot.
//!
//! The fix is to focus the *viewport* on the dominant cluster of
//! components without dropping any geometry from the *render*. The
//! outlying islands still get drawn — they just fall outside the
//! viewBox and clip naturally.
//!
//! ## Algorithm
//!
//! 1. Decompose every input geometry into its component polygons.
//! 2. Pick the largest by signed area as the seed.
//! 3. Threshold = `factor × diagonal(seed.bbox)` (default factor 0.15).
//! 4. Iteratively grow the cluster: any polygon whose bbox is within
//!    `threshold` of *any* polygon already in the cluster joins.
//!    Repeat until stable.
//! 5. Viewport bbox = union of clustered bboxes.
//!
//! Components with no polygon area (lines, points) are ignored — the
//! caller should fall back to a full-bbox union for those cases.
//!
//! ## Verified behaviour at factor=0.15
//!
//! | Feature                    | Cluster                       |
//! |----------------------------|-------------------------------|
//! | `country/USA`              | CONUS only (Alaska clipped)   |
//! | `country/FRA`              | Metropolitan + Corsica        |
//! | `country/NZL`              | North Is + South Is + Stewart |
//! | `country/ITA`              | Peninsula + Sicily + Sardinia |
//! | `country/DEU`              | (single component)            |
//! | `subregion/Western Europe` | Mainland + UK + Ireland       |
//!
//! Outlying components (Alaska, Svalbard, Iceland, …) are still
//! *rendered* (their geometry is untouched); they just fall outside
//! the SVG viewBox and clip naturally.

use crate::geometry::{ring_bbox, BBox, Geometry, LonLat};

/// Default cluster threshold: outlying components within
/// `0.15 × diagonal_of_largest` of the cluster join the viewport.
///
/// Chosen so European maps don't include Svalbard or Iceland in the
/// viewport (which would force a tall narrow frame), while Sicily,
/// Sardinia, Corsica, the UK, and Ireland remain inside. Alaska also
/// falls outside CONUS at this threshold — that's an acceptable
/// trade-off; Alaska is still drawn at the top of the SVG.
pub const DEFAULT_CLUSTER_FACTOR: f64 = 0.15;

/// Compute the viewport bbox using the "main cluster" heuristic. Every
/// polygon component across `geoms` is considered. Returns `None` if
/// the input has no polygon areas (lines/points/empty) — caller should
/// fall back to a full-bbox union.
pub fn main_cluster_bbox(geoms: &[&Geometry], factor: f64) -> Option<BBox> {
    // Collect every polygon component as (area, bbox).
    let mut comps: Vec<(f64, BBox)> = Vec::new();
    for g in geoms {
        for_each_polygon(g, |outer| {
            let area = polygon_area(outer).abs();
            if area > 0.0 {
                comps.push((area, ring_bbox(outer)));
            }
        });
    }
    if comps.is_empty() {
        return None;
    }

    // Seed: largest by area.
    let seed_idx = comps
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.0.partial_cmp(&b.1.0).unwrap())
        .map(|(i, _)| i)
        .unwrap();

    let threshold = factor * bbox_diagonal(comps[seed_idx].1);

    // Grow cluster: BFS over bbox-adjacency.
    let mut in_cluster = vec![false; comps.len()];
    in_cluster[seed_idx] = true;
    let mut frontier = vec![seed_idx];

    while let Some(i) = frontier.pop() {
        let bb_i = comps[i].1;
        for j in 0..comps.len() {
            if in_cluster[j] {
                continue;
            }
            if bbox_distance(bb_i, comps[j].1) <= threshold {
                in_cluster[j] = true;
                frontier.push(j);
            }
        }
    }

    // Union the clustered bboxes.
    let mut bb = BBox::empty();
    for (i, (_, b)) in comps.iter().enumerate() {
        if in_cluster[i] {
            bb.extend(*b);
        }
    }
    if bb.is_empty() { None } else { Some(bb) }
}

/// Walk every polygon outer ring inside a geometry. Lines/points are
/// skipped silently — `main_cluster_bbox` falls back to a full-bbox
/// union for those geometries via its `None` return.
fn for_each_polygon<F: FnMut(&[LonLat])>(g: &Geometry, mut f: F) {
    match g {
        Geometry::Polygon { outer, .. } => f(outer),
        Geometry::MultiPolygon(polys) => {
            for p in polys {
                f(&p.outer);
            }
        }
        _ => {}
    }
}

fn polygon_area(ring: &[LonLat]) -> f64 {
    if ring.len() < 3 {
        return 0.0;
    }
    let mut acc = 0.0;
    for i in 0..ring.len() {
        let j = (i + 1) % ring.len();
        acc += ring[i].lon * ring[j].lat - ring[j].lon * ring[i].lat;
    }
    acc * 0.5
}

fn bbox_diagonal(b: BBox) -> f64 {
    if b.is_empty() {
        return 0.0;
    }
    let dx = b.max_lon - b.min_lon;
    let dy = b.max_lat - b.min_lat;
    (dx * dx + dy * dy).sqrt()
}

/// Minkowski-style bbox-to-bbox distance. Zero when the bboxes overlap
/// or touch; otherwise the L2 distance between their nearest corners.
fn bbox_distance(a: BBox, b: BBox) -> f64 {
    let dx = if a.max_lon < b.min_lon {
        b.min_lon - a.max_lon
    } else if b.max_lon < a.min_lon {
        a.min_lon - b.max_lon
    } else {
        0.0
    };
    let dy = if a.max_lat < b.min_lat {
        b.min_lat - a.max_lat
    } else if b.max_lat < a.min_lat {
        a.min_lat - b.max_lat
    } else {
        0.0
    };
    (dx * dx + dy * dy).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::Polygon;

    fn square_poly(min_lon: f64, min_lat: f64, side: f64) -> Polygon {
        let mx = min_lon + side;
        let my = min_lat + side;
        Polygon {
            outer: vec![
                LonLat { lon: min_lon, lat: min_lat },
                LonLat { lon: mx, lat: min_lat },
                LonLat { lon: mx, lat: my },
                LonLat { lon: min_lon, lat: my },
                LonLat { lon: min_lon, lat: min_lat },
            ],
            holes: vec![],
        }
    }

    #[test]
    fn empty_geom_returns_none() {
        let g = Geometry::MultiPolygon(vec![]);
        assert!(main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).is_none());
    }

    #[test]
    fn lines_only_returns_none() {
        let g = Geometry::LineString(vec![
            LonLat { lon: 0.0, lat: 0.0 },
            LonLat { lon: 10.0, lat: 0.0 },
        ]);
        assert!(main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).is_none());
    }

    #[test]
    fn single_polygon_returns_full_bbox() {
        let g = Geometry::MultiPolygon(vec![square_poly(0.0, 0.0, 10.0)]);
        let bb = main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).unwrap();
        assert!((bb.min_lon - 0.0).abs() < 1e-9);
        assert!((bb.max_lon - 10.0).abs() < 1e-9);
        assert!((bb.min_lat - 0.0).abs() < 1e-9);
        assert!((bb.max_lat - 10.0).abs() < 1e-9);
    }

    #[test]
    fn close_polygons_cluster_together() {
        // Big square 0,0–10,10 (diag ≈ 14.14, threshold ≈ 4.24).
        // Small square 12,0–13,1 — only 2° away → joins cluster.
        let g = Geometry::MultiPolygon(vec![
            square_poly(0.0, 0.0, 10.0),
            square_poly(12.0, 0.0, 1.0),
        ]);
        let bb = main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).unwrap();
        assert!((bb.max_lon - 13.0).abs() < 1e-6, "max_lon={}", bb.max_lon);
    }

    #[test]
    fn far_polygons_excluded() {
        // Big square 0,0–10,10 (threshold ≈ 4.24). Small square at
        // 100,100 is 127° away → excluded.
        let g = Geometry::MultiPolygon(vec![
            square_poly(0.0, 0.0, 10.0),
            square_poly(100.0, 100.0, 1.0),
        ]);
        let bb = main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).unwrap();
        assert!((bb.max_lon - 10.0).abs() < 1e-6);
        assert!((bb.max_lat - 10.0).abs() < 1e-6);
    }

    fn rect_poly(min_lon: f64, min_lat: f64, w: f64, h: f64) -> Polygon {
        let mx = min_lon + w;
        let my = min_lat + h;
        Polygon {
            outer: vec![
                LonLat { lon: min_lon, lat: min_lat },
                LonLat { lon: mx, lat: min_lat },
                LonLat { lon: mx, lat: my },
                LonLat { lon: min_lon, lat: my },
                LonLat { lon: min_lon, lat: min_lat },
            ],
            holes: vec![],
        }
    }

    #[test]
    fn usa_like_excludes_alaska_and_hawaii() {
        // Synthetic CONUS at (-125,25)-(-65,49), 60×24°. Diagonal
        // ≈ 64.6°; threshold at factor=0.15 ≈ 9.7°.
        let conus = rect_poly(-125.0, 25.0, 60.0, 24.0);
        // Synthetic Alaska at (-168,55)-(-141,71), 27×16°. Closest
        // to CONUS at (-141, 49 vs 55) → distance = √(16²+6²)≈17° —
        // beyond the 9.7° threshold.
        let alaska = rect_poly(-168.0, 55.0, 27.0, 16.0);
        // Synthetic Hawaii at (-160, 19)-(-155,22). Distance from
        // CONUS ≈ 30° — also excluded.
        let hawaii = rect_poly(-160.0, 19.0, 5.0, 3.0);

        let g = Geometry::MultiPolygon(vec![conus, alaska, hawaii]);
        let bb = main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).unwrap();
        // Cluster should be CONUS only.
        assert!((bb.min_lon - -125.0).abs() < 1e-6);
        assert!((bb.max_lon - -65.0).abs() < 1e-6);
        assert!((bb.min_lat - 25.0).abs() < 1e-6);
        assert!((bb.max_lat - 49.0).abs() < 1e-6);
    }

    #[test]
    fn highlight_unaffected_by_cluster() {
        // This module doesn't know about highlights — the pipeline
        // composes them on top. Just verify cluster works on plain
        // input.
        let g = Geometry::MultiPolygon(vec![square_poly(0.0, 0.0, 5.0)]);
        let bb = main_cluster_bbox(&[&g], DEFAULT_CLUSTER_FACTOR).unwrap();
        assert!((bb.max_lon - 5.0).abs() < 1e-9);
    }

    #[test]
    fn bbox_distance_overlap_is_zero() {
        let a = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 5.0, max_lat: 5.0 };
        let b = BBox { min_lon: 3.0, min_lat: 3.0, max_lon: 7.0, max_lat: 7.0 };
        assert_eq!(bbox_distance(a, b), 0.0);
    }

    #[test]
    fn bbox_distance_horizontal_gap() {
        let a = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 5.0, max_lat: 5.0 };
        let b = BBox { min_lon: 10.0, min_lat: 0.0, max_lon: 15.0, max_lat: 5.0 };
        assert!((bbox_distance(a, b) - 5.0).abs() < 1e-9);
    }

    #[test]
    fn bbox_distance_diagonal_gap() {
        let a = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 5.0, max_lat: 5.0 };
        let b = BBox { min_lon: 8.0, min_lat: 9.0, max_lon: 10.0, max_lat: 12.0 };
        // Gap dx=3, dy=4 → distance = 5.
        assert!((bbox_distance(a, b) - 5.0).abs() < 1e-9);
    }

    #[test]
    fn polygon_area_signed() {
        let ccw = vec![
            LonLat { lon: 0.0, lat: 0.0 },
            LonLat { lon: 1.0, lat: 0.0 },
            LonLat { lon: 1.0, lat: 1.0 },
            LonLat { lon: 0.0, lat: 1.0 },
        ];
        assert!((polygon_area(&ccw) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn polygon_area_too_few_points() {
        let pts = vec![LonLat { lon: 0.0, lat: 0.0 }, LonLat { lon: 1.0, lat: 0.0 }];
        assert_eq!(polygon_area(&pts), 0.0);
    }

    #[test]
    fn cluster_across_multiple_geoms() {
        // Two separate Geometry inputs; cluster should consider both.
        let g1 = Geometry::MultiPolygon(vec![square_poly(0.0, 0.0, 10.0)]);
        let g2 = Geometry::MultiPolygon(vec![square_poly(12.0, 0.0, 1.0)]);
        let bb = main_cluster_bbox(&[&g1, &g2], DEFAULT_CLUSTER_FACTOR).unwrap();
        assert!((bb.max_lon - 13.0).abs() < 1e-6);
    }
}
