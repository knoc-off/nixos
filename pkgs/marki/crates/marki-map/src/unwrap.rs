//! Coordinate-frame rotation and wrap-meridian ring splitting.
//!
//! ## Why
//!
//! After `rotate_geometry` shifts every vertex into the chosen central
//! frame, polygons that *genuinely wrap around the globe* (e.g.
//! Russia's outer boundary, which traces from western Russia all the
//! way to its Chukotka peninsula past the dateline) end up with two
//! halves on opposite sides of the wrap meridian (`central ± 180°`).
//!
//! If we hand such a ring to the SVG composer it draws an `M…L…` path
//! that connects e.g. `(190°, 70°)` to `(−168°, 65°)` — a straight
//! line streaking ~360° across the canvas.
//!
//! `split_at_wrap` cuts every wrapping ring into two (or more) proper
//! closed polygons at the wrap meridian. Each fragment closes along
//! the wrap meridian itself. The "near" fragment (e.g. ~99% of
//! Russia) renders normally; the "far" fragment (Chukotka tip) sits
//! off-canvas and gets clipped naturally by the SVG `viewBox`.
//!
//! ## Rotation
//!
//! `rotate_geometry` shifts every vertex's longitude so it lies in
//! `(central − 180°, central + 180°]`. After rotation, the only place
//! a ring can "teleport" is across the wrap meridian — exactly where
//! `split_at_wrap` cuts. The two operations are designed to be used
//! together.

use crate::geometry::{best_outer_for, Geometry, LonLat, Polygon};

/// Rotate one longitude so its offset from `central` lies in
/// `(-180°, 180°]`. The output may exceed `±180°` — that's fine for
/// downstream projection (Mercator is just `lon.to_radians()`).
pub fn rotate_lon(lon: f64, central: f64) -> f64 {
    let offset = ((lon - central + 540.0) % 360.0 + 360.0) % 360.0 - 180.0;
    let offset = if offset <= -180.0 { offset + 360.0 } else { offset };
    central + offset
}

/// Rotate every vertex of `geom` so that all longitudes sit in a
/// contiguous range centred on `central`. This is a pure coordinate
/// shift — shape integrity is preserved (all vertices move uniformly).
pub fn rotate_geometry(geom: &mut Geometry, central: f64) {
    fn rotate_ring(ring: &mut [LonLat], c: f64) {
        for p in ring.iter_mut() {
            p.lon = rotate_lon(p.lon, c);
        }
    }
    match geom {
        Geometry::Point(p) => p.lon = rotate_lon(p.lon, central),
        Geometry::LineString(line) => rotate_ring(line, central),
        Geometry::MultiLineString(lines) => {
            for line in lines.iter_mut() {
                rotate_ring(line, central);
            }
        }
        Geometry::Polygon { outer, holes } => {
            rotate_ring(outer, central);
            for h in holes.iter_mut() {
                rotate_ring(h, central);
            }
        }
        Geometry::MultiPolygon(polys) => {
            for p in polys.iter_mut() {
                rotate_ring(&mut p.outer, central);
                for h in p.holes.iter_mut() {
                    rotate_ring(h, central);
                }
            }
        }
    }
}

/// Threshold for detecting a wrap-meridian crossing: any consecutive
/// pair of vertices with `|Δlon|` exceeding this much has teleported
/// across the wrap. Real geographic edges never jump more than ~180°
/// (the dataset's vertex density is far higher than that), so 180°
/// is a safe lower bound. We pick `200°` to leave headroom for
/// numerical noise on near-boundary edges.
const WRAP_DELTA_THRESHOLD: f64 = 200.0;

/// Split any rings that cross the wrap meridian (`central ± 180°`)
/// into separate closed pieces.
///
/// A "wrap crossing" is any pair of consecutive vertices whose
/// longitudes differ by more than [`WRAP_DELTA_THRESHOLD`] — that
/// only happens when an edge teleports across the wrap.
///
/// Polygons that don't wrap pass through unchanged. A wrapping
/// `Polygon` becomes a `MultiPolygon` with one fragment per side.
/// Lines split into a `MultiLineString`.
pub fn split_at_wrap(geom: Geometry, central: f64) -> Geometry {
    let wrap = central + 180.0;
    match geom {
        Geometry::Point(p) => Geometry::Point(p),
        Geometry::LineString(line) => {
            let segments = split_line(&line, wrap);
            if segments.len() == 1 {
                Geometry::LineString(segments.into_iter().next().unwrap())
            } else {
                Geometry::MultiLineString(segments)
            }
        }
        Geometry::MultiLineString(lines) => {
            let mut all = Vec::new();
            for line in lines {
                all.extend(split_line(&line, wrap));
            }
            Geometry::MultiLineString(all)
        }
        Geometry::Polygon { outer, holes } => {
            let polys = split_polygon(&outer, &holes, wrap);
            if polys.len() == 1 {
                let p = polys.into_iter().next().unwrap();
                Geometry::Polygon {
                    outer: p.outer,
                    holes: p.holes,
                }
            } else {
                Geometry::MultiPolygon(polys)
            }
        }
        Geometry::MultiPolygon(polys) => {
            let mut all = Vec::new();
            for p in polys {
                all.extend(split_polygon(&p.outer, &p.holes, wrap));
            }
            Geometry::MultiPolygon(all)
        }
    }
}

/// Split one polygon (outer + its holes) at the wrap meridian.
/// Returns one `Polygon` per side of the wrap. Holes are reassigned
/// to whichever surviving outer fragment contains them.
fn split_polygon(outer: &[LonLat], holes: &[Vec<LonLat>], wrap: f64) -> Vec<Polygon> {
    let outer_frags = split_ring(outer, wrap);
    if outer_frags.len() == 1 {
        // No wrap crossing — passthrough with the original holes.
        return vec![Polygon {
            outer: outer_frags.into_iter().next().unwrap(),
            holes: holes.to_vec(),
        }];
    }

    // Each outer fragment becomes its own Polygon. Holes get assigned
    // by bbox containment — same heuristic used by overpass relation
    // assembly. A hole that itself crosses the wrap is split first;
    // each hole fragment is then assigned independently.
    let mut polys: Vec<Polygon> = outer_frags
        .into_iter()
        .map(|outer| Polygon {
            outer,
            holes: Vec::new(),
        })
        .collect();

    for h in holes {
        for frag in split_ring(h, wrap) {
            if let Some(idx) = best_outer_for(&frag, &polys) {
                polys[idx].holes.push(frag);
            }
            // If no enclosing outer fragment exists (shouldn't happen
            // for clean data), drop the hole — better than attaching
            // it to the wrong outer.
        }
    }
    polys
}

/// Split one ring at the wrap meridian. Walks consecutive vertex
/// pairs, finds wrap crossings, and emits one closed sub-ring per
/// side. Returns the ring unchanged if it doesn't cross.
fn split_ring(ring: &[LonLat], wrap: f64) -> Vec<Vec<LonLat>> {
    if ring.len() < 3 || !ring_crosses_wrap(ring) {
        return vec![ring.to_vec()];
    }

    // We treat the ring as a closed loop — iterate edges including
    // the closing edge from last → first. The shapefile loader
    // duplicates the first vertex at the end, so we drop the
    // duplicate to avoid emitting a zero-length closing edge.
    let pts: Vec<LonLat> = if ring.first() == ring.last() && ring.len() > 1 {
        ring[..ring.len() - 1].to_vec()
    } else {
        ring.to_vec()
    };
    let n = pts.len();

    // Walk the loop; on each crossing record the pre- and post-
    // crossing points (interpolated at the wrap meridian) and end
    // the current segment / start a new one.
    let mut segments: Vec<Vec<LonLat>> = Vec::new();
    let mut current: Vec<LonLat> = Vec::with_capacity(n);
    current.push(pts[0]);

    for i in 0..n {
        let a = pts[i];
        let b = pts[(i + 1) % n];
        let dx = b.lon - a.lon;
        if dx.abs() > WRAP_DELTA_THRESHOLD {
            // Crossing edge. Interpolate the crossing latitude. We
            // unwrap `b` by ±360° so it sits on the same side as
            // `a`, then linearly interpolate at the wrap longitude.
            let b_unwrapped_lon = if dx < 0.0 {
                b.lon + 360.0
            } else {
                b.lon - 360.0
            };
            let cross_lat = interpolate_at(a.lon, a.lat, b_unwrapped_lon, b.lat, wrap);

            // Direction of the wrap. If `dx < 0` (e.g. 185° → -170°),
            // the edge crossed eastward past `wrap`: `a`'s side ends
            // at the right (+wrap) and `b`'s side begins at the left
            // (wrap-360°). If `dx > 0` (e.g. -170° → 185°), the edge
            // crossed westward past `wrap-360°`: `a` exits left, `b`
            // enters right.
            let (exit_lon, entry_lon) = if dx < 0.0 {
                (wrap, wrap - 360.0)
            } else {
                (wrap - 360.0, wrap)
            };
            current.push(LonLat { lon: exit_lon, lat: cross_lat });
            segments.push(std::mem::take(&mut current));

            current.push(LonLat { lon: entry_lon, lat: cross_lat });
            current.push(b);
        } else {
            // Normal edge: append the next vertex if it isn't the
            // ring-closure duplicate (the for-loop's modulo step
            // does that on the last iteration).
            if i + 1 < n {
                current.push(b);
            }
        }
    }

    // The final segment connects back to the first one — they're
    // halves of the same ring on the same side of the wrap. Merge
    // them so we don't end up with a "half-open" segment.
    if !current.is_empty() {
        if let Some(first) = segments.first_mut() {
            // The current segment's tail meets the first segment's
            // head at the original ring start (pts[0]). Skip the
            // duplicate when stitching.
            let merged_head: Vec<LonLat> = current
                .into_iter()
                .chain(first.iter().skip(1).copied())
                .collect();
            *first = merged_head;
        } else {
            segments.push(current);
        }
    }

    // Close each segment so it's a proper polygon ring (first == last).
    for seg in segments.iter_mut() {
        if let (Some(&first), Some(&last)) = (seg.first(), seg.last()) {
            if first != last {
                seg.push(first);
            }
        }
    }

    segments
}

/// True iff any consecutive pair of vertices in `ring` (including the
/// wrap from last → first) has a longitude jump beyond the threshold.
fn ring_crosses_wrap(ring: &[LonLat]) -> bool {
    if ring.len() < 2 {
        return false;
    }
    for i in 0..ring.len() - 1 {
        if (ring[i + 1].lon - ring[i].lon).abs() > WRAP_DELTA_THRESHOLD {
            return true;
        }
    }
    // Closing edge.
    let first = ring[0];
    let last = ring[ring.len() - 1];
    if first != last {
        if (first.lon - last.lon).abs() > WRAP_DELTA_THRESHOLD {
            return true;
        }
    }
    false
}

/// Split a polyline (LineString) at the wrap meridian.
/// Each crossing breaks the line into two segments — the line is
/// open, so no closing edges to merge.
fn split_line(pts: &[LonLat], wrap: f64) -> Vec<Vec<LonLat>> {
    if pts.len() < 2 {
        return vec![pts.to_vec()];
    }
    let mut segments: Vec<Vec<LonLat>> = Vec::new();
    let mut current: Vec<LonLat> = vec![pts[0]];

    for i in 0..pts.len() - 1 {
        let a = pts[i];
        let b = pts[i + 1];
        let dx = b.lon - a.lon;
        if dx.abs() > WRAP_DELTA_THRESHOLD {
            let b_unwrapped_lon = if dx < 0.0 {
                b.lon + 360.0
            } else {
                b.lon - 360.0
            };
            let cross_lat = interpolate_at(a.lon, a.lat, b_unwrapped_lon, b.lat, wrap);
            let (exit_lon, entry_lon) = if dx < 0.0 {
                (wrap, wrap - 360.0)
            } else {
                (wrap - 360.0, wrap)
            };
            current.push(LonLat { lon: exit_lon, lat: cross_lat });
            segments.push(std::mem::take(&mut current));

            current.push(LonLat { lon: entry_lon, lat: cross_lat });
            current.push(b);
        } else {
            current.push(b);
        }
    }
    if !current.is_empty() {
        segments.push(current);
    }
    // Filter out degenerate single-point segments produced by an
    // immediate re-crossing.
    segments.retain(|s| s.len() >= 2);
    if segments.is_empty() {
        return vec![pts.to_vec()];
    }
    segments
}

/// Linear interpolation of latitude along an edge whose endpoints'
/// longitudes have been unwrapped onto a single contiguous line.
fn interpolate_at(a_lon: f64, a_lat: f64, b_lon: f64, b_lat: f64, target_lon: f64) -> f64 {
    let dx = b_lon - a_lon;
    if dx.abs() < 1e-12 {
        return a_lat;
    }
    let t = (target_lon - a_lon) / dx;
    a_lat + t * (b_lat - a_lat)
}

#[cfg(test)]
mod tests {
    use super::*;

    // ---------- rotate_lon / rotate_geometry ----------

    #[test]
    fn rotate_lon_identity_when_close_to_central() {
        let c = 0.0;
        assert!((rotate_lon(45.0, c) - 45.0).abs() < 1e-9);
        assert!((rotate_lon(-90.0, c) - -90.0).abs() < 1e-9);
        assert!((rotate_lon(179.0, c) - 179.0).abs() < 1e-9);
    }

    #[test]
    fn rotate_lon_shifts_far_side() {
        // central = 174.5°. A vertex at -176° (Chatham) should land
        // near +184°.
        let c = 174.5;
        let r = rotate_lon(-176.0, c);
        assert!((r - 184.0).abs() < 1e-6, "got {r}");
    }

    #[test]
    fn rotate_lon_round_trip_identity() {
        for &lon in &[-179.0, -1.0, 0.0, 45.0, 174.5, 178.0] {
            for &c in &[-120.0, 0.0, 30.0, 174.5] {
                let r = rotate_lon(lon, c);
                let delta = (r - lon).rem_euclid(360.0);
                assert!(
                    delta < 1e-6 || (360.0 - delta) < 1e-6,
                    "lon={lon} c={c} r={r} delta={delta}"
                );
            }
        }
    }

    #[test]
    fn rotate_geometry_polygon_uniform() {
        let mut g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 170.0, lat: -40.0 },
                LonLat { lon: 175.0, lat: -40.0 },
                LonLat { lon: 175.0, lat: -35.0 },
                LonLat { lon: 170.0, lat: -35.0 },
                LonLat { lon: 170.0, lat: -40.0 },
            ],
            holes: vec![],
        };
        rotate_geometry(&mut g, 172.5);
        if let Geometry::Polygon { outer, .. } = &g {
            assert!((outer[0].lon - 170.0).abs() < 1e-6);
            assert!((outer[1].lon - 175.0).abs() < 1e-6);
        } else {
            panic!("expected polygon");
        }
    }

    #[test]
    fn rotate_geometry_far_side_polygon() {
        let mut g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: -176.0, lat: -44.0 },
                LonLat { lon: -174.0, lat: -44.0 },
                LonLat { lon: -174.0, lat: -43.0 },
                LonLat { lon: -176.0, lat: -43.0 },
                LonLat { lon: -176.0, lat: -44.0 },
            ],
            holes: vec![],
        };
        rotate_geometry(&mut g, 174.5);
        if let Geometry::Polygon { outer, .. } = &g {
            assert!(outer[0].lon > 180.0, "got {}", outer[0].lon);
            assert!((outer[0].lon - 184.0).abs() < 1.0);
        } else {
            panic!("expected polygon");
        }
    }

    #[test]
    fn rotate_geometry_multipolygon_all_rings() {
        let mut g = Geometry::MultiPolygon(vec![
            Polygon {
                outer: vec![LonLat { lon: -176.0, lat: 0.0 }],
                holes: vec![],
            },
            Polygon {
                outer: vec![LonLat { lon: 175.0, lat: 0.0 }],
                holes: vec![],
            },
        ]);
        rotate_geometry(&mut g, 174.5);
        if let Geometry::MultiPolygon(polys) = &g {
            assert!(polys[0].outer[0].lon > 180.0);
            assert!((polys[1].outer[0].lon - 175.0).abs() < 1e-6);
        } else {
            panic!("expected multipolygon");
        }
    }

    // ---------- split_at_wrap ----------

    #[test]
    fn ring_no_crossing_passthrough() {
        // Square polygon at 0–10°, wrap at 200° — no crossing.
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 5.0 },
                LonLat { lon: 0.0, lat: 5.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let result = split_at_wrap(g, 20.0); // wrap = 200°
        match result {
            Geometry::Polygon { outer, .. } => assert_eq!(outer.len(), 5),
            other => panic!("expected single Polygon, got {other:?}"),
        }
    }

    #[test]
    fn ring_two_crossings_splits_into_two_polygons() {
        // Ring crossing wrap=190° at two edges. Vertices:
        //   (180, 60), (185, 60), (-170, 60), (-170, 50), (185, 50), (180, 50)
        // (after rotation, the -170 points represent Chukotka after wrap)
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: 185.0, lat: 60.0 },
                LonLat { lon: -170.0, lat: 60.0 }, // crosses wrap
                LonLat { lon: -170.0, lat: 50.0 },
                LonLat { lon: 185.0, lat: 50.0 },  // crosses back
                LonLat { lon: 180.0, lat: 50.0 },
                LonLat { lon: 180.0, lat: 60.0 },
            ],
            holes: vec![],
        };
        let result = split_at_wrap(g, 10.0); // wrap = 190°
        match result {
            Geometry::MultiPolygon(polys) => {
                assert_eq!(polys.len(), 2, "expected 2 fragments, got {}", polys.len());
                // Each fragment should be closed (first == last).
                for p in &polys {
                    assert_eq!(p.outer.first(), p.outer.last(),
                        "fragment not closed: {:?}", p.outer);
                    assert!(p.outer.len() >= 4, "degenerate fragment: {:?}", p.outer);
                }
                // One fragment lives on each side of the wrap.
                let lon_means: Vec<f64> = polys.iter()
                    .map(|p| {
                        let sum: f64 = p.outer.iter().map(|v| v.lon).sum();
                        sum / p.outer.len() as f64
                    })
                    .collect();
                let near = lon_means.iter().any(|&m| m > 180.0);
                let far = lon_means.iter().any(|&m| m < -160.0);
                assert!(near, "no near-side fragment: means {lon_means:?}");
                assert!(far, "no far-side fragment: means {lon_means:?}");
            }
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    #[test]
    fn ring_crosses_wrap_detection() {
        let no_cross = vec![
            LonLat { lon: 0.0, lat: 0.0 },
            LonLat { lon: 10.0, lat: 0.0 },
            LonLat { lon: 10.0, lat: 5.0 },
            LonLat { lon: 0.0, lat: 5.0 },
        ];
        assert!(!ring_crosses_wrap(&no_cross));

        let crosses = vec![
            LonLat { lon: 185.0, lat: 0.0 },
            LonLat { lon: -170.0, lat: 0.0 }, // 355° jump
        ];
        assert!(ring_crosses_wrap(&crosses));
    }

    #[test]
    fn split_multipolygon_only_wrapping_member_splits() {
        // One wrapping polygon + one normal polygon.
        let wrapping = Polygon {
            outer: vec![
                LonLat { lon: 180.0, lat: 60.0 },
                LonLat { lon: -170.0, lat: 60.0 },
                LonLat { lon: -170.0, lat: 50.0 },
                LonLat { lon: 180.0, lat: 50.0 },
                LonLat { lon: 180.0, lat: 60.0 },
            ],
            holes: vec![],
        };
        let normal = Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 5.0 },
                LonLat { lon: 0.0, lat: 5.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let g = Geometry::MultiPolygon(vec![wrapping, normal]);
        let result = split_at_wrap(g, 10.0); // wrap = 190°
        match result {
            Geometry::MultiPolygon(polys) => {
                // 2 fragments from the wrapping poly + 1 unchanged = 3.
                assert_eq!(polys.len(), 3, "got {} polygons", polys.len());
            }
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    #[test]
    fn split_linestring_into_multiline() {
        // Line from 175° to 195° wrapping to -175° (after rotation).
        let g = Geometry::LineString(vec![
            LonLat { lon: 175.0, lat: 0.0 },
            LonLat { lon: 185.0, lat: 0.0 },
            LonLat { lon: -170.0, lat: 0.0 }, // crosses wrap=190°
            LonLat { lon: -160.0, lat: 0.0 },
        ]);
        let result = split_at_wrap(g, 10.0);
        match result {
            Geometry::MultiLineString(lines) => {
                assert_eq!(lines.len(), 2, "expected 2 segments, got {}", lines.len());
                // Each segment has at least 2 points.
                for l in &lines {
                    assert!(l.len() >= 2);
                }
            }
            other => panic!("expected MultiLineString, got {other:?}"),
        }
    }

    #[test]
    fn point_passthrough() {
        let g = Geometry::Point(LonLat { lon: 175.0, lat: 0.0 });
        let result = split_at_wrap(g, 10.0);
        match result {
            Geometry::Point(p) => assert_eq!(p.lon, 175.0),
            other => panic!("expected Point, got {other:?}"),
        }
    }

    #[test]
    fn russia_like_split_smoke_test() {
        // Synthetic Russia-shaped ring rotated so its eastern tip
        // wraps. Vertices (after rotation by central=10.5°):
        //   western Russia (27°), through Siberia (170°), to Chukotka
        //   tip (192° → -168°), back along the coast.
        // The ring should split into a near fragment (main Russia)
        // and a far fragment (tiny Chukotka).
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 27.0, lat: 60.0 },
                LonLat { lon: 100.0, lat: 70.0 },
                LonLat { lon: 170.0, lat: 70.0 },
                LonLat { lon: 190.0, lat: 67.0 },
                LonLat { lon: -168.0, lat: 65.0 }, // Chukotka tip (after rotation)
                LonLat { lon: 190.0, lat: 60.0 },  // back across
                LonLat { lon: 170.0, lat: 55.0 },
                LonLat { lon: 100.0, lat: 50.0 },
                LonLat { lon: 27.0, lat: 50.0 },
                LonLat { lon: 27.0, lat: 60.0 },
            ],
            holes: vec![],
        };
        let result = split_at_wrap(g, 10.5); // wrap = 190.5°
        match result {
            Geometry::MultiPolygon(polys) => {
                assert_eq!(polys.len(), 2, "got {} polygons", polys.len());
                // The bigger fragment should be the main Russia.
                let bigger = polys.iter()
                    .max_by(|a, b| a.outer.len().cmp(&b.outer.len()))
                    .unwrap();
                assert!(bigger.outer.len() >= 8, "main fragment too small");
            }
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    #[test]
    fn polygon_with_holes_no_crossing() {
        // Sanity check: holes survive a no-crossing passthrough.
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![vec![
                LonLat { lon: 3.0, lat: 3.0 },
                LonLat { lon: 7.0, lat: 3.0 },
                LonLat { lon: 7.0, lat: 7.0 },
                LonLat { lon: 3.0, lat: 7.0 },
                LonLat { lon: 3.0, lat: 3.0 },
            ]],
        };
        let result = split_at_wrap(g, 100.0);
        match result {
            Geometry::Polygon { holes, .. } => assert_eq!(holes.len(), 1),
            other => panic!("expected single Polygon, got {other:?}"),
        }
    }

    #[test]
    fn interpolate_at_basic() {
        // Edge from (0, 0) to (10, 100), interpolate at lon=5: lat=50.
        let lat = interpolate_at(0.0, 0.0, 10.0, 100.0, 5.0);
        assert!((lat - 50.0).abs() < 1e-9, "got {lat}");
    }

    #[test]
    fn interpolate_at_degenerate_zero_dx() {
        // a_lon == b_lon: should not panic, returns a_lat.
        let lat = interpolate_at(5.0, 42.0, 5.0, 99.0, 5.0);
        assert_eq!(lat, 42.0);
    }
}
