//! Geometry-density viewport trimming.
//!
//! ## Why
//!
//! After the cluster heuristic picks a viewport bbox, sparse high-
//! latitude regions (the northern tip of Norway/Finland, the southern
//! tip of New Zealand, …) can dominate the canvas because Mercator
//! projection stretches them disproportionately. A pan-European card
//! ends up at 250×400 even though >90% of the visible content fits
//! comfortably below 65°N.
//!
//! Trimming inspects the actual geometry density inside the bbox and
//! shrinks any edge whose outermost slice contains less than
//! `min_density` of the total polygon vertices. The dense central
//! body of the map keeps its full extent; the sparse fringe gets
//! cropped off.
//!
//! A hard `min_aspect` Mercator floor catches degenerate cases where
//! density alone leaves the bbox too tall/narrow.
//!
//! ## Algorithm
//!
//! 1. Bin every polygon outer-ring vertex into a fixed-resolution
//!    grid (lat × lon).
//! 2. From each edge of the bbox, walk inward one slice at a time.
//!    Track cumulative vertex count for that edge's strip; while the
//!    cumulative fraction stays below `min_density`, advance the
//!    edge inward.
//! 3. After all four edges have been trimmed, check the Mercator
//!    aspect ratio. If it's still below `min_aspect`, trim further
//!    from whichever latitude edge is furthest from the equator
//!    (Mercator's high-distortion end).
//!
//! Lines / points contribute their vertices the same way polygons do.

use crate::geometry::{BBox, Geometry, LonLat};
use crate::project::mercator_y;

/// Number of bins along each axis. 64 bins on a 36°-tall European
/// viewport gives ~0.5° per bin — fine enough to follow country
/// outlines, coarse enough to avoid noisy thresholds from the
/// vertex-density variation between simplified and detailed regions.
const BIN_COUNT: usize = 64;

/// Trim sparse edges of `bb` based on geometry density.
///
/// `min_density` is the cumulative vertex fraction below which an
/// edge gets trimmed. `min_aspect` is the Mercator aspect floor
/// (after density trimming, a too-narrow viewport gets further
/// trimmed from its extreme-latitude edge).
///
/// Returns the trimmed bbox. If `min_density <= 0.0`, density
/// trimming is skipped (only the aspect floor applies). If both are
/// 0/disabled, returns `bb` unchanged.
pub fn trim_sparse_edges(
    bb: BBox,
    geoms: &[&Geometry],
    min_density: f64,
    min_aspect: f64,
) -> BBox {
    if bb.is_empty() {
        return bb;
    }

    // Build the histogram once; we'll re-query it for each edge.
    let hist = Histogram::build(bb, geoms);
    if hist.total == 0 {
        return bb;
    }

    let mut trimmed = bb;
    if min_density > 0.0 {
        trimmed = trim_edge(trimmed, &hist, min_density, Edge::Top);
        trimmed = trim_edge(trimmed, &hist, min_density, Edge::Bottom);
        trimmed = trim_edge(trimmed, &hist, min_density, Edge::Left);
        trimmed = trim_edge(trimmed, &hist, min_density, Edge::Right);
    }

    if min_aspect > 0.0 {
        trimmed = constrain_aspect(trimmed, min_aspect);
    }

    trimmed
}

// ---------- histogram ----------

/// 2-D vertex count grid over the original bbox.
struct Histogram {
    /// `bins[lat_idx][lon_idx]` — vertex count for that cell. Indexed
    /// from south (0) to north (BIN_COUNT-1) and west to east.
    bins: Vec<Vec<u32>>,
    /// Lat/lon span captured by the histogram.
    bb: BBox,
    /// Sum of all bin counts.
    total: u32,
}

impl Histogram {
    fn build(bb: BBox, geoms: &[&Geometry]) -> Self {
        let mut bins = vec![vec![0u32; BIN_COUNT]; BIN_COUNT];
        let mut total: u32 = 0;
        let lon_span = (bb.max_lon - bb.min_lon).max(f64::MIN_POSITIVE);
        let lat_span = (bb.max_lat - bb.min_lat).max(f64::MIN_POSITIVE);

        let mut accumulate = |p: LonLat| {
            // Vertices outside the bbox don't count — trimming is
            // computed relative to the bbox we were handed.
            if p.lon < bb.min_lon
                || p.lon > bb.max_lon
                || p.lat < bb.min_lat
                || p.lat > bb.max_lat
            {
                return;
            }
            let lon_idx = (((p.lon - bb.min_lon) / lon_span) * BIN_COUNT as f64) as usize;
            let lat_idx = (((p.lat - bb.min_lat) / lat_span) * BIN_COUNT as f64) as usize;
            let lon_idx = lon_idx.min(BIN_COUNT - 1);
            let lat_idx = lat_idx.min(BIN_COUNT - 1);
            bins[lat_idx][lon_idx] += 1;
            total += 1;
        };
        for g in geoms {
            walk_vertices(g, &mut accumulate);
        }
        Self { bins, bb, total }
    }

    /// Sum of all bins in row `lat_idx`.
    fn row_sum(&self, lat_idx: usize) -> u32 {
        self.bins[lat_idx].iter().sum()
    }

    /// Sum of all bins in column `lon_idx`.
    fn col_sum(&self, lon_idx: usize) -> u32 {
        self.bins.iter().map(|row| row[lon_idx]).sum()
    }
}

fn walk_vertices<F: FnMut(LonLat)>(g: &Geometry, f: &mut F) {
    match g {
        Geometry::Point(p) => f(*p),
        Geometry::LineString(line) => {
            for p in line {
                f(*p);
            }
        }
        Geometry::MultiLineString(lines) => {
            for line in lines {
                for p in line {
                    f(*p);
                }
            }
        }
        Geometry::Polygon { outer, .. } => {
            for p in outer {
                f(*p);
            }
        }
        Geometry::MultiPolygon(polys) => {
            for poly in polys {
                for p in &poly.outer {
                    f(*p);
                }
            }
        }
    }
}

// ---------- per-edge trimming ----------

/// Which edge of the bbox to trim inward.
enum Edge {
    Top,
    Bottom,
    Left,
    Right,
}

/// Walk inward from `edge` while the cumulative vertex fraction in
/// the trimmed strip stays below `min_density`.
fn trim_edge(mut bb: BBox, hist: &Histogram, min_density: f64, edge: Edge) -> BBox {
    let total = hist.total as f64;

    let is_lat = matches!(edge, Edge::Top | Edge::Bottom);
    let from_max = matches!(edge, Edge::Top | Edge::Right);

    let (origin, span) = if is_lat {
        (hist.bb.min_lat, (hist.bb.max_lat - hist.bb.min_lat).max(f64::MIN_POSITIVE))
    } else {
        (hist.bb.min_lon, (hist.bb.max_lon - hist.bb.min_lon).max(f64::MIN_POSITIVE))
    };
    let bin_size = span / BIN_COUNT as f64;

    // The opposite-edge value we must not cross.
    let opposite = match (&edge, from_max) {
        (_, true) => if is_lat { bb.min_lat } else { bb.min_lon },
        _ => if is_lat { bb.max_lat } else { bb.max_lon },
    };

    let bin_sum = |i: usize| -> u32 {
        if is_lat { hist.row_sum(i) } else { hist.col_sum(i) }
    };

    let mut cum: f64 = 0.0;

    // Walk from the edge inward: max-side walks high→low, min-side
    // walks low→high.
    let mut it: Box<dyn Iterator<Item = usize>> = if from_max {
        Box::new((0..BIN_COUNT).rev())
    } else {
        Box::new(0..BIN_COUNT)
    };

    for i in it.by_ref() {
        let lo = origin + bin_size * i as f64;
        let hi = origin + bin_size * (i as f64 + 1.0);

        // Have we passed the opposite boundary?
        let outer = if from_max { hi } else { lo };
        if from_max { if outer <= opposite { break; } }
        else        { if outer >= opposite { break; } }

        let next = cum + bin_sum(i) as f64 / total;
        if next > min_density {
            break;
        }
        cum = next;

        // Move the edge inward to this bin's inner face.
        let inner = if from_max { lo } else { hi };
        match edge {
            Edge::Top    => bb.max_lat = inner,
            Edge::Bottom => bb.min_lat = inner,
            Edge::Right  => bb.max_lon = inner,
            Edge::Left   => bb.min_lon = inner,
        }
    }

    // Guard against degenerate collapse.
    match edge {
        Edge::Top    if bb.max_lat <= bb.min_lat => bb.max_lat = hist.bb.max_lat,
        Edge::Bottom if bb.min_lat >= bb.max_lat => bb.min_lat = hist.bb.min_lat,
        Edge::Left   if bb.min_lon >= bb.max_lon => bb.min_lon = hist.bb.min_lon,
        Edge::Right  if bb.max_lon <= bb.min_lon => bb.max_lon = hist.bb.max_lon,
        _ => {}
    }

    bb
}

// ---------- aspect floor ----------

/// If the Mercator aspect of `bb` is below `min_aspect`, trim
/// latitude from whichever edge is furthest from the equator.
/// Iterates until the floor is met (or the bbox would collapse).
fn constrain_aspect(mut bb: BBox, min_aspect: f64) -> BBox {
    for _ in 0..20 {
        let aspect = mercator_aspect(bb);
        if aspect >= min_aspect || bb.max_lat <= bb.min_lat + 1e-6 {
            break;
        }
        // Trim from the extreme-latitude end (whichever |lat| is
        // larger). This is where Mercator distortion is worst.
        if bb.max_lat.abs() > bb.min_lat.abs() {
            // Top is the extreme — trim it down.
            let target_dy = (bb.max_lon - bb.min_lon).to_radians() / min_aspect;
            let new_top = inverse_mercator_y(mercator_y(bb.min_lat) + target_dy);
            if new_top.is_finite() && new_top > bb.min_lat && new_top < bb.max_lat {
                bb.max_lat = new_top;
            } else {
                break;
            }
        } else {
            // Bottom is the extreme — trim it up.
            let target_dy = (bb.max_lon - bb.min_lon).to_radians() / min_aspect;
            let new_bottom = inverse_mercator_y(mercator_y(bb.max_lat) - target_dy);
            if new_bottom.is_finite() && new_bottom < bb.max_lat && new_bottom > bb.min_lat {
                bb.min_lat = new_bottom;
            } else {
                break;
            }
        }
    }
    bb
}

fn inverse_mercator_y(y: f64) -> f64 {
    (y.exp().atan() * 2.0 - std::f64::consts::FRAC_PI_2).to_degrees()
}

fn mercator_aspect(bb: BBox) -> f64 {
    let dx = (bb.max_lon - bb.min_lon).to_radians();
    let dy = (mercator_y(bb.max_lat) - mercator_y(bb.min_lat)).max(1e-12);
    dx / dy
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::Polygon;

    fn ring(min_lon: f64, min_lat: f64, w: f64, h: f64) -> Vec<LonLat> {
        let mx = min_lon + w;
        let my = min_lat + h;
        vec![
            LonLat { lon: min_lon, lat: min_lat },
            LonLat { lon: mx, lat: min_lat },
            LonLat { lon: mx, lat: my },
            LonLat { lon: min_lon, lat: my },
            LonLat { lon: min_lon, lat: min_lat },
        ]
    }

    #[test]
    fn empty_geom_returns_original() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        let g = Geometry::MultiPolygon(vec![]);
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        assert!((out.min_lon - bb.min_lon).abs() < 1e-9);
        assert!((out.max_lon - bb.max_lon).abs() < 1e-9);
        assert!((out.min_lat - bb.min_lat).abs() < 1e-9);
        assert!((out.max_lat - bb.max_lat).abs() < 1e-9);
    }

    #[test]
    fn density_disabled_no_trim() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // One small polygon at the bottom only — would normally trim
        // the top, but min_density=0 disables trimming.
        let g = Geometry::Polygon { outer: ring(0.0, 0.0, 10.0, 1.0), holes: vec![] };
        let out = trim_sparse_edges(bb, &[&g], 0.0, 0.0);
        assert!((out.max_lat - 10.0).abs() < 1e-9);
    }

    #[test]
    fn sparse_top_trimmed() {
        // Geometry concentrated in lat 0-7; viewport is 0-10. Top
        // should be trimmed.
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // Big rectangle at the bottom, no geometry above lat 7.
        let g = Geometry::Polygon {
            outer: ring(0.0, 0.0, 10.0, 7.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        // Should trim the top (no vertices above lat 7).
        assert!(out.max_lat < 9.0, "expected trimmed top, got max_lat={}", out.max_lat);
        // Bottom should NOT trim — bottom edge has dense geometry.
        assert!((out.min_lat - 0.0).abs() < 1e-9);
    }

    #[test]
    fn sparse_bottom_trimmed() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        let g = Geometry::Polygon {
            outer: ring(0.0, 3.0, 10.0, 7.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        assert!(out.min_lat > 1.0, "expected trimmed bottom, got min_lat={}", out.min_lat);
        assert!((out.max_lat - 10.0).abs() < 1e-9);
    }

    #[test]
    fn sparse_both_lat_ends_trimmed() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // Geometry only in middle band lat 3-7.
        let g = Geometry::Polygon {
            outer: ring(0.0, 3.0, 10.0, 4.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        assert!(out.min_lat > 1.0);
        assert!(out.max_lat < 9.0);
    }

    #[test]
    fn sparse_left_right_trimmed() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // Geometry concentrated in lon 3-7.
        let g = Geometry::Polygon {
            outer: ring(3.0, 0.0, 4.0, 10.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        assert!(out.min_lon > 1.0, "got {}", out.min_lon);
        assert!(out.max_lon < 9.0, "got {}", out.max_lon);
    }

    #[test]
    fn dense_uniform_no_trim() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // Polygon fills the whole bbox with vertices on every side.
        let g = Geometry::Polygon {
            outer: ring(0.0, 0.0, 10.0, 10.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.05, 0.0);
        // Vertices live at the corners — each edge has 2/4 of total.
        // 50% > 5%, so no trimming.
        assert!((out.min_lon - 0.0).abs() < 1e-9);
        assert!((out.max_lon - 10.0).abs() < 1e-9);
        assert!((out.min_lat - 0.0).abs() < 1e-9);
        assert!((out.max_lat - 10.0).abs() < 1e-9);
    }

    #[test]
    fn aspect_floor_kicks_in() {
        // Bbox at 35..71 N, lon 0..10 — extremely tall in Mercator.
        let bb = BBox { min_lon: 0.0, min_lat: 35.0, max_lon: 10.0, max_lat: 71.0 };
        // Dense uniform vertices everywhere so density trim doesn't
        // shrink it.
        let g = Geometry::MultiPolygon(
            (0..36)
                .map(|lat| Polygon {
                    outer: ring(0.0, 35.0 + lat as f64, 10.0, 1.0),
                    holes: vec![],
                })
                .collect(),
        );
        let original_aspect = mercator_aspect(bb);
        assert!(original_aspect < 0.6, "test setup: original aspect should be narrow, got {original_aspect}");
        let out = trim_sparse_edges(bb, &[&g], 0.0, 0.6);
        let new_aspect = mercator_aspect(out);
        assert!(new_aspect >= 0.6 - 1e-3, "expected aspect >= 0.6, got {new_aspect}");
        // Should have trimmed the top (extreme lat).
        assert!(out.max_lat < 71.0, "expected top trimmed, got max_lat={}", out.max_lat);
    }

    #[test]
    fn aspect_floor_disabled_when_zero() {
        let bb = BBox { min_lon: 0.0, min_lat: 35.0, max_lon: 10.0, max_lat: 71.0 };
        let g = Geometry::Polygon {
            outer: ring(0.0, 35.0, 10.0, 36.0),
            holes: vec![],
        };
        let out = trim_sparse_edges(bb, &[&g], 0.0, 0.0);
        assert!((out.max_lat - 71.0).abs() < 1e-9);
        assert!((out.min_lat - 35.0).abs() < 1e-9);
    }

    #[test]
    fn density_trim_doesnt_collapse_bbox() {
        // Pathological: only one vertex in the whole bbox — trimming
        // shouldn't collapse to nothing.
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        let g = Geometry::Point(LonLat { lon: 5.0, lat: 5.0 });
        let out = trim_sparse_edges(bb, &[&g], 0.5, 0.0);
        assert!(out.max_lon > out.min_lon);
        assert!(out.max_lat > out.min_lat);
    }

    #[test]
    fn histogram_total_matches_vertex_count() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        let g = Geometry::Polygon {
            outer: ring(2.0, 2.0, 5.0, 5.0),  // 5 vertices including closure dup
            holes: vec![],
        };
        let h = Histogram::build(bb, &[&g]);
        assert_eq!(h.total, 5);
    }

    #[test]
    fn histogram_ignores_outside_bbox() {
        let bb = BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 };
        // Polygon partially outside the bbox — only the inside-bbox
        // vertices should count.
        let g = Geometry::Polygon {
            outer: ring(-5.0, -5.0, 10.0, 10.0),
            holes: vec![],
        };
        let h = Histogram::build(bb, &[&g]);
        // 5 vertices total in the ring; vertices: (-5,-5), (5,-5),
        // (5,5), (-5,5), (-5,-5). Only (5,5) is strictly inside.
        // (-5,-5) etc. are outside.
        assert!(h.total <= 1, "got {} (expected at most 1)", h.total);
    }

    #[test]
    fn mercator_y_inverse_round_trip() {
        for lat in [-80.0, -45.0, 0.0, 35.0, 60.0, 80.0] {
            let y = mercator_y(lat);
            let back = inverse_mercator_y(y);
            assert!((back - lat).abs() < 1e-6, "lat={lat} round-trip={back}");
        }
    }
}
