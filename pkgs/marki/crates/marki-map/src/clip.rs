//! Viewport clipping. Drops geometry components fully outside a clip
//! bbox; clips border-straddling rings with Sutherland-Hodgman so they
//! end with clean edges along the clip boundary.
//!
//! ## Why
//!
//! After the cluster heuristic picks a viewport, the rendered SVG
//! still contains every vertex of every feature — including off-screen
//! continents (French Polynesia, eastern Siberia, …) and the unwrapped
//! eastern ends of polygons that wrap the globe. The SVG `viewBox`
//! clips visually, but those off-screen vertices still bloat the file.
//!
//! Clipping happens **after** the viewport is computed (so we know the
//! bounds) but **before** projection (so the math is in lon/lat
//! degrees, not pixels). It's also before Douglas-Peucker
//! simplification in `compose.rs`, so simplification operates on
//! fewer vertices.
//!
//! ## Two tiers
//!
//! 1. **Drop whole components.** Each polygon / line component whose
//!    bbox is fully outside the clip bbox is discarded. O(1) per
//!    component; eliminates entire countries in one check.
//! 2. **Sutherland-Hodgman clip.** Components that straddle the clip
//!    boundary are clipped against each of the four edges in turn.
//!    The result is a proper closed polygon (or open polyline) with
//!    new vertices interpolated at each crossing.

use crate::geometry::{BBox, Geometry, LonLat, Polygon};

/// Clip a geometry to `clip`. Any component fully outside is dropped;
/// any component that straddles is clipped to the bbox.
///
/// Returns `Geometry::default()` (an empty `MultiPolygon`) when the
/// entire geometry lies outside the clip — the renderer's compose
/// step treats that as "nothing to draw" and emits no path.
pub fn clip_geometry(geom: Geometry, clip: BBox) -> Geometry {
    match geom {
        Geometry::Point(p) => {
            if point_in_bbox(p, clip) {
                Geometry::Point(p)
            } else {
                Geometry::default()
            }
        }
        Geometry::LineString(line) => {
            let segments = clip_line(&line, clip);
            match segments.len() {
                0 => Geometry::default(),
                1 => Geometry::LineString(segments.into_iter().next().unwrap()),
                _ => Geometry::MultiLineString(segments),
            }
        }
        Geometry::MultiLineString(lines) => {
            let mut all = Vec::new();
            for line in lines {
                if !ring_bbox(&line).intersects(&clip) {
                    continue;
                }
                all.extend(clip_line(&line, clip));
            }
            match all.len() {
                0 => Geometry::default(),
                1 => Geometry::LineString(all.into_iter().next().unwrap()),
                _ => Geometry::MultiLineString(all),
            }
        }
        Geometry::Polygon { outer, holes } => {
            match clip_polygon(&outer, &holes, clip) {
                Some(p) => Geometry::Polygon {
                    outer: p.outer,
                    holes: p.holes,
                },
                None => Geometry::default(),
            }
        }
        Geometry::MultiPolygon(polys) => {
            let mut survivors: Vec<Polygon> = Vec::new();
            for p in polys {
                if let Some(clipped) = clip_polygon(&p.outer, &p.holes, clip) {
                    survivors.push(clipped);
                }
            }
            match survivors.len() {
                0 => Geometry::default(),
                1 => {
                    let p = survivors.into_iter().next().unwrap();
                    Geometry::Polygon {
                        outer: p.outer,
                        holes: p.holes,
                    }
                }
                _ => Geometry::MultiPolygon(survivors),
            }
        }
    }
}

/// Clip one polygon (outer + its holes) to `clip`. Returns `None` when
/// the outer ring is fully outside the clip (or clips to nothing).
fn clip_polygon(outer: &[LonLat], holes: &[Vec<LonLat>], clip: BBox) -> Option<Polygon> {
    // Tier 1: bbox-based component drop.
    if !ring_bbox(outer).intersects(&clip) {
        return None;
    }
    // Tier 2: Sutherland-Hodgman clip of the outer ring.
    let clipped_outer = sh_clip_ring(outer, clip);
    if clipped_outer.len() < 3 {
        return None;
    }
    // Holes: each one independently bbox-tested then clipped. A hole
    // that falls entirely outside the clip simply disappears.
    let mut clipped_holes: Vec<Vec<LonLat>> = Vec::new();
    for h in holes {
        if !ring_bbox(h).intersects(&clip) {
            continue;
        }
        let r = sh_clip_ring(h, clip);
        if r.len() >= 3 {
            clipped_holes.push(r);
        }
    }
    Some(Polygon {
        outer: clipped_outer,
        holes: clipped_holes,
    })
}

/// Clip an open polyline against the bbox. The line may be cut into
/// multiple segments where it exits and re-enters the clip region.
fn clip_line(pts: &[LonLat], clip: BBox) -> Vec<Vec<LonLat>> {
    if pts.len() < 2 {
        return Vec::new();
    }
    if !ring_bbox(pts).intersects(&clip) {
        return Vec::new();
    }
    let mut segments: Vec<Vec<LonLat>> = Vec::new();
    let mut current: Vec<LonLat> = Vec::new();

    let mut prev = pts[0];
    let mut prev_in = point_in_bbox(prev, clip);
    if prev_in {
        current.push(prev);
    }

    for &cur in &pts[1..] {
        let cur_in = point_in_bbox(cur, clip);
        match (prev_in, cur_in) {
            (true, true) => {
                current.push(cur);
            }
            (true, false) => {
                // Exiting: append the boundary intersection, finish segment.
                if let Some(p) = clip_segment_to_bbox(prev, cur, clip) {
                    current.push(p.1);
                }
                if current.len() >= 2 {
                    segments.push(std::mem::take(&mut current));
                } else {
                    current.clear();
                }
            }
            (false, true) => {
                // Entering: start a new segment at the boundary.
                if let Some(p) = clip_segment_to_bbox(prev, cur, clip) {
                    current.push(p.0);
                }
                current.push(cur);
            }
            (false, false) => {
                // Both outside — but the segment may still cross the
                // clip box twice (a chord). Emit as its own segment.
                if let Some((a, b)) = clip_segment_to_bbox(prev, cur, clip) {
                    segments.push(vec![a, b]);
                }
            }
        }
        prev = cur;
        prev_in = cur_in;
    }
    if current.len() >= 2 {
        segments.push(current);
    }
    segments
}

/// Clip the segment `a → b` to the bbox using Liang-Barsky. Returns
/// the (possibly clipped) endpoints, or `None` if the segment is
/// entirely outside the bbox.
fn clip_segment_to_bbox(a: LonLat, b: LonLat, clip: BBox) -> Option<(LonLat, LonLat)> {
    // Parametric: P(t) = a + t*(b-a), t in [0, 1].
    let dx = b.lon - a.lon;
    let dy = b.lat - a.lat;
    let mut t0 = 0.0_f64;
    let mut t1 = 1.0_f64;
    let edges = [
        (-dx, a.lon - clip.min_lon), // left:   p < min_lon  is outside
        ( dx, clip.max_lon - a.lon), // right:  p > max_lon
        (-dy, a.lat - clip.min_lat), // bottom: p < min_lat
        ( dy, clip.max_lat - a.lat), // top:    p > max_lat
    ];
    for (p, q) in edges {
        if p == 0.0 {
            if q < 0.0 {
                return None; // Parallel and outside.
            }
            // Parallel and inside — no constraint from this edge.
            continue;
        }
        let t = q / p;
        if p < 0.0 {
            // Entering: tighten the lower bound.
            if t > t1 {
                return None;
            }
            if t > t0 {
                t0 = t;
            }
        } else {
            // Leaving: tighten the upper bound.
            if t < t0 {
                return None;
            }
            if t < t1 {
                t1 = t;
            }
        }
    }
    Some((
        LonLat {
            lon: a.lon + t0 * dx,
            lat: a.lat + t0 * dy,
        },
        LonLat {
            lon: a.lon + t1 * dx,
            lat: a.lat + t1 * dy,
        },
    ))
}

/// Sutherland-Hodgman: clip a polygon ring against each of the four
/// bbox edges in turn. The output ring is closed and has new vertices
/// interpolated at every clip-edge crossing.
fn sh_clip_ring(ring: &[LonLat], clip: BBox) -> Vec<LonLat> {
    if ring.is_empty() {
        return Vec::new();
    }
    let r = clip_against_edge(ring, Edge::Left(clip.min_lon));
    let r = clip_against_edge(&r, Edge::Right(clip.max_lon));
    let r = clip_against_edge(&r, Edge::Bottom(clip.min_lat));
    let r = clip_against_edge(&r, Edge::Top(clip.max_lat));
    // Close the ring (first == last) if non-empty and the loader
    // didn't already.
    if r.len() >= 3 {
        let mut out = r;
        if out.first() != out.last() {
            out.push(out[0]);
        }
        out
    } else {
        Vec::new()
    }
}

#[derive(Clone, Copy)]
enum Edge {
    Left(f64),
    Right(f64),
    Bottom(f64),
    Top(f64),
}

impl Edge {
    fn inside(&self, p: LonLat) -> bool {
        match *self {
            Edge::Left(x) => p.lon >= x,
            Edge::Right(x) => p.lon <= x,
            Edge::Bottom(y) => p.lat >= y,
            Edge::Top(y) => p.lat <= y,
        }
    }

    /// Intersect the segment `a → b` with this edge. Caller guarantees
    /// the two endpoints are on opposite sides of the edge.
    fn intersect(&self, a: LonLat, b: LonLat) -> LonLat {
        match *self {
            Edge::Left(x) | Edge::Right(x) => {
                let dx = b.lon - a.lon;
                if dx.abs() < 1e-12 {
                    return LonLat { lon: x, lat: a.lat };
                }
                let t = (x - a.lon) / dx;
                LonLat {
                    lon: x,
                    lat: a.lat + t * (b.lat - a.lat),
                }
            }
            Edge::Bottom(y) | Edge::Top(y) => {
                let dy = b.lat - a.lat;
                if dy.abs() < 1e-12 {
                    return LonLat { lon: a.lon, lat: y };
                }
                let t = (y - a.lat) / dy;
                LonLat {
                    lon: a.lon + t * (b.lon - a.lon),
                    lat: y,
                }
            }
        }
    }
}

/// Clip a ring against a single half-plane edge. Standard
/// Sutherland-Hodgman: walk the input edges, classify each endpoint,
/// emit endpoints / intersections per the four cases.
fn clip_against_edge(ring: &[LonLat], edge: Edge) -> Vec<LonLat> {
    if ring.is_empty() {
        return Vec::new();
    }
    let n = ring.len();
    // Drop the trailing closure-duplicate vertex if present so we
    // don't double-emit the closure point.
    let working: &[LonLat] = if ring.first() == ring.last() && n > 1 {
        &ring[..n - 1]
    } else {
        ring
    };
    let mut out: Vec<LonLat> = Vec::with_capacity(working.len() + 1);

    if working.is_empty() {
        return out;
    }

    let mut prev = *working.last().unwrap();
    let mut prev_in = edge.inside(prev);
    for &cur in working {
        let cur_in = edge.inside(cur);
        match (prev_in, cur_in) {
            (true, true) => out.push(cur),
            (true, false) => out.push(edge.intersect(prev, cur)),
            (false, true) => {
                out.push(edge.intersect(prev, cur));
                out.push(cur);
            }
            (false, false) => {}
        }
        prev = cur;
        prev_in = cur_in;
    }
    out
}

fn point_in_bbox(p: LonLat, bb: BBox) -> bool {
    p.lon >= bb.min_lon && p.lon <= bb.max_lon && p.lat >= bb.min_lat && p.lat <= bb.max_lat
}

fn ring_bbox(pts: &[LonLat]) -> BBox {
    let mut bb = BBox::empty();
    for p in pts {
        bb.extend_point(*p);
    }
    bb
}

#[cfg(test)]
mod tests {
    use super::*;

    fn square_ring(min_lon: f64, min_lat: f64, w: f64, h: f64) -> Vec<LonLat> {
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

    fn unit_clip() -> BBox {
        BBox { min_lon: 0.0, min_lat: 0.0, max_lon: 10.0, max_lat: 10.0 }
    }

    // ---------- Sutherland-Hodgman primitives ----------

    #[test]
    fn sh_clip_ring_fully_inside_passthrough() {
        let ring = square_ring(2.0, 2.0, 5.0, 5.0);
        let out = sh_clip_ring(&ring, unit_clip());
        assert_eq!(out.len(), 5);
        // All input vertices preserved (modulo first==last closure).
        assert_eq!(out[0].lon, 2.0);
        assert_eq!(out[2].lon, 7.0);
    }

    #[test]
    fn sh_clip_ring_fully_outside_empty() {
        let ring = square_ring(20.0, 20.0, 5.0, 5.0);
        let out = sh_clip_ring(&ring, unit_clip());
        assert!(out.is_empty(), "got {} vertices", out.len());
    }

    #[test]
    fn sh_clip_ring_one_corner_clipped() {
        // Square at (-2, -2) to (5, 5) — bottom-left corner outside.
        let ring = square_ring(-2.0, -2.0, 7.0, 7.0);
        let out = sh_clip_ring(&ring, unit_clip());
        // Result should be a 4-vertex pentagon-ish shape clipped to
        // (0,0)-(5,5); first==last gives 5+ vertices.
        assert!(out.len() >= 4, "got {:?}", out);
        for v in &out {
            assert!(v.lon >= -1e-9 && v.lon <= 10.0 + 1e-9, "{:?}", v);
            assert!(v.lat >= -1e-9 && v.lat <= 10.0 + 1e-9, "{:?}", v);
        }
        // The clip introduced new vertices on x=0 and y=0.
        let on_left = out.iter().filter(|v| v.lon.abs() < 1e-6).count();
        let on_bottom = out.iter().filter(|v| v.lat.abs() < 1e-6).count();
        assert!(on_left >= 1, "no vertex on left edge: {:?}", out);
        assert!(on_bottom >= 1, "no vertex on bottom edge: {:?}", out);
    }

    #[test]
    fn sh_clip_ring_straddling_left_edge() {
        // Polygon at (-5, 2) to (5, 8) — straddles only the left edge.
        let ring = square_ring(-5.0, 2.0, 10.0, 6.0);
        let out = sh_clip_ring(&ring, unit_clip());
        // Resulting shape is a rectangle (0,2)-(5,8) with closure.
        assert!(out.len() >= 5);
        let min_lon = out.iter().map(|v| v.lon).fold(f64::INFINITY, f64::min);
        let max_lon = out.iter().map(|v| v.lon).fold(f64::NEG_INFINITY, f64::max);
        assert!((min_lon - 0.0).abs() < 1e-6, "got min_lon={min_lon}");
        assert!((max_lon - 5.0).abs() < 1e-6, "got max_lon={max_lon}");
    }

    // ---------- clip_polygon ----------

    #[test]
    fn polygon_fully_inside_passthrough() {
        let g = Geometry::Polygon {
            outer: square_ring(2.0, 2.0, 5.0, 5.0),
            holes: vec![],
        };
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::Polygon { outer, .. } => assert_eq!(outer.len(), 5),
            other => panic!("expected Polygon, got {other:?}"),
        }
    }

    #[test]
    fn polygon_fully_outside_dropped() {
        let g = Geometry::Polygon {
            outer: square_ring(20.0, 20.0, 5.0, 5.0),
            holes: vec![],
        };
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::MultiPolygon(polys) => assert!(polys.is_empty()),
            other => panic!("expected empty MultiPolygon, got {other:?}"),
        }
    }

    #[test]
    fn hole_fully_inside_survives() {
        let g = Geometry::Polygon {
            outer: square_ring(0.0, 0.0, 10.0, 10.0),
            holes: vec![square_ring(3.0, 3.0, 4.0, 4.0)],
        };
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::Polygon { holes, .. } => assert_eq!(holes.len(), 1),
            other => panic!("expected Polygon, got {other:?}"),
        }
    }

    #[test]
    fn hole_fully_outside_dropped_but_outer_survives() {
        // Outer fully inside; hole entirely outside the clip (which
        // shouldn't normally happen for valid input but we must
        // tolerate it).
        let g = Geometry::Polygon {
            outer: square_ring(0.0, 0.0, 10.0, 10.0),
            holes: vec![square_ring(20.0, 20.0, 1.0, 1.0)],
        };
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::Polygon { holes, .. } => assert!(holes.is_empty()),
            other => panic!("expected Polygon, got {other:?}"),
        }
    }

    // ---------- clip_geometry on MultiPolygon ----------

    #[test]
    fn multipolygon_drops_outside_keeps_inside() {
        let inside = Polygon { outer: square_ring(2.0, 2.0, 3.0, 3.0), holes: vec![] };
        let outside = Polygon { outer: square_ring(20.0, 20.0, 3.0, 3.0), holes: vec![] };
        let g = Geometry::MultiPolygon(vec![inside, outside]);
        let out = clip_geometry(g, unit_clip());
        // Two surviving outer rings (one inside) → simplifies to a Polygon
        // because the MultiPolygon collapse rule emits a single Polygon
        // when only one survives.
        match out {
            Geometry::Polygon { outer, .. } => {
                assert_eq!(outer.len(), 5);
                assert!(outer.iter().all(|v| v.lon >= 0.0 && v.lon <= 10.0));
            }
            other => panic!("expected single Polygon, got {other:?}"),
        }
    }

    #[test]
    fn multipolygon_with_straddler_clips_clean() {
        let inside = Polygon { outer: square_ring(2.0, 2.0, 3.0, 3.0), holes: vec![] };
        let straddler = Polygon { outer: square_ring(-5.0, 2.0, 10.0, 6.0), holes: vec![] };
        let g = Geometry::MultiPolygon(vec![inside, straddler]);
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::MultiPolygon(polys) => {
                assert_eq!(polys.len(), 2);
                for p in &polys {
                    for v in &p.outer {
                        assert!(v.lon >= -1e-9 && v.lon <= 10.0 + 1e-9);
                    }
                }
            }
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    // ---------- LineString clipping ----------

    #[test]
    fn linestring_clip_basic() {
        // Line from (-5, 5) to (15, 5) — both endpoints outside, but
        // the middle crosses the clip box.
        let g = Geometry::LineString(vec![
            LonLat { lon: -5.0, lat: 5.0 },
            LonLat { lon: 15.0, lat: 5.0 },
        ]);
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::LineString(pts) => {
                assert_eq!(pts.len(), 2);
                assert!((pts[0].lon - 0.0).abs() < 1e-6);
                assert!((pts[1].lon - 10.0).abs() < 1e-6);
            }
            other => panic!("expected LineString, got {other:?}"),
        }
    }

    #[test]
    fn linestring_one_endpoint_inside() {
        let g = Geometry::LineString(vec![
            LonLat { lon: 5.0, lat: 5.0 }, // inside
            LonLat { lon: 15.0, lat: 5.0 }, // outside
        ]);
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::LineString(pts) => {
                assert_eq!(pts.len(), 2);
                assert!((pts[0].lon - 5.0).abs() < 1e-6);
                assert!((pts[1].lon - 10.0).abs() < 1e-6);
            }
            other => panic!("expected LineString, got {other:?}"),
        }
    }

    #[test]
    fn linestring_fully_outside_dropped() {
        let g = Geometry::LineString(vec![
            LonLat { lon: 20.0, lat: 5.0 },
            LonLat { lon: 30.0, lat: 5.0 },
        ]);
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::MultiPolygon(polys) => assert!(polys.is_empty()),
            other => panic!("expected empty default, got {other:?}"),
        }
    }

    #[test]
    fn linestring_re_entering_produces_two_segments() {
        // Line: in → out → in → out.
        let g = Geometry::LineString(vec![
            LonLat { lon: 5.0, lat: 5.0 },   // in
            LonLat { lon: 15.0, lat: 5.0 },  // out
            LonLat { lon: 15.0, lat: 7.0 },  // out
            LonLat { lon: 5.0, lat: 7.0 },   // in
            LonLat { lon: 15.0, lat: 7.0 },  // out
        ]);
        let out = clip_geometry(g, unit_clip());
        match out {
            Geometry::MultiLineString(lines) => {
                assert!(lines.len() >= 2, "expected >=2 segments, got {}", lines.len());
            }
            other => panic!("expected MultiLineString, got {other:?}"),
        }
    }

    // ---------- Point ----------

    #[test]
    fn point_inside_kept() {
        let g = Geometry::Point(LonLat { lon: 5.0, lat: 5.0 });
        match clip_geometry(g, unit_clip()) {
            Geometry::Point(p) => assert_eq!(p.lon, 5.0),
            other => panic!("expected Point, got {other:?}"),
        }
    }

    #[test]
    fn point_outside_dropped() {
        let g = Geometry::Point(LonLat { lon: 20.0, lat: 5.0 });
        match clip_geometry(g, unit_clip()) {
            Geometry::MultiPolygon(polys) => assert!(polys.is_empty()),
            other => panic!("expected empty default, got {other:?}"),
        }
    }

    // ---------- Liang-Barsky line-segment clip primitive ----------

    #[test]
    fn segment_clip_both_inside() {
        let bb = unit_clip();
        let r = clip_segment_to_bbox(
            LonLat { lon: 2.0, lat: 2.0 },
            LonLat { lon: 8.0, lat: 8.0 },
            bb,
        ).unwrap();
        assert_eq!(r.0.lon, 2.0);
        assert_eq!(r.1.lon, 8.0);
    }

    #[test]
    fn segment_clip_one_outside() {
        let bb = unit_clip();
        let r = clip_segment_to_bbox(
            LonLat { lon: -5.0, lat: 5.0 },
            LonLat { lon: 5.0, lat: 5.0 },
            bb,
        ).unwrap();
        assert!((r.0.lon - 0.0).abs() < 1e-6);
        assert_eq!(r.1.lon, 5.0);
    }

    #[test]
    fn segment_clip_chord() {
        let bb = unit_clip();
        let r = clip_segment_to_bbox(
            LonLat { lon: -5.0, lat: 5.0 },
            LonLat { lon: 15.0, lat: 5.0 },
            bb,
        ).unwrap();
        assert!((r.0.lon - 0.0).abs() < 1e-6);
        assert!((r.1.lon - 10.0).abs() < 1e-6);
    }

    #[test]
    fn segment_clip_fully_outside() {
        let bb = unit_clip();
        let r = clip_segment_to_bbox(
            LonLat { lon: 20.0, lat: 5.0 },
            LonLat { lon: 30.0, lat: 5.0 },
            bb,
        );
        assert!(r.is_none());
    }
}
