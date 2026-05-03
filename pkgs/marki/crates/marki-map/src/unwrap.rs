//! Optimal central-meridian computation for world-spanning feature
//! sets.
//!
//! ## Why
//!
//! Naively projecting features that straddle the antimeridian (NZ +
//! Fiji, Russia + Alaska, …) yields a ~350°-wide bbox that fills the
//! whole canvas with empty ocean. The fix is to pick a *rotated*
//! central meridian: every Mercator-style projection effectively wraps
//! longitude around a chosen prime meridian; if we pick one that lies
//! antipodal to the data, the data forms a tight contiguous range.
//!
//! ## Algorithm
//!
//! 1. Sample every vertex longitude, normalised to `[0°, 360°)`.
//! 2. Sort and find the largest empty arc between consecutive samples
//!    (treated circularly).
//! 3. The optimal central meridian is the **antipode of the arc's
//!    centre** — equivalently, the meridian that bisects the data.
//!
//! After rotation, the data's enclosing arc is `360° − largest_gap`,
//! which is provably the smallest possible.
//!
//! For NZ + Fiji this turns a 354°-wide world-spanning bbox into a
//! ~19° tight bbox centred on ~174.5°E.

use crate::geometry::{Geometry, LonLat};

/// Pick the optimal central meridian (in degrees, in `(-180°, 180°]`)
/// for a set of vertex longitudes. Returns `0.0` for empty input.
pub fn central_meridian(lons: impl IntoIterator<Item = f64>) -> f64 {
    let mut samples: Vec<f64> = lons
        .into_iter()
        .filter(|l| l.is_finite())
        .map(|l| ((l % 360.0) + 360.0) % 360.0)
        .collect();
    if samples.is_empty() {
        return 0.0;
    }
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());

    // Find the largest gap between consecutive samples, with the array
    // treated circularly (wrap from last back to first + 360°).
    let n = samples.len();
    let mut largest = -1.0;
    let mut gap_centre: f64 = 0.0;
    for i in 0..n {
        let cur = samples[i];
        let next = if i + 1 < n {
            samples[i + 1]
        } else {
            samples[0] + 360.0
        };
        let gap = next - cur;
        if gap > largest {
            largest = gap;
            gap_centre = (cur + next) * 0.5;
        }
    }

    // The central meridian sits opposite the empty arc's centre.
    wrap_to_180(gap_centre - 180.0)
}

/// Map a longitude into `(-180°, 180°]`.
fn wrap_to_180(lon: f64) -> f64 {
    let mut x = ((lon + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;
    // (-180, 180]: the boundary case ends up at -180 due to mod; lift it.
    if x <= -180.0 {
        x += 360.0;
    }
    x
}

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

/// Append every vertex longitude of `g` to `out`. Used to gather the
/// vertex sample passed to [`central_meridian`].
pub fn collect_lons(g: &Geometry, out: &mut Vec<f64>) {
    match g {
        Geometry::Point(p) => out.push(p.lon),
        Geometry::LineString(line) => out.extend(line.iter().map(|p| p.lon)),
        Geometry::MultiLineString(lines) => {
            for line in lines {
                out.extend(line.iter().map(|p| p.lon));
            }
        }
        Geometry::Polygon { outer, holes } => {
            out.extend(outer.iter().map(|p| p.lon));
            for h in holes {
                out.extend(h.iter().map(|p| p.lon));
            }
        }
        Geometry::MultiPolygon(polys) => {
            for p in polys {
                out.extend(p.outer.iter().map(|p| p.lon));
                for h in &p.holes {
                    out.extend(h.iter().map(|p| p.lon));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::Polygon;

    #[test]
    fn empty_input_returns_zero() {
        assert_eq!(central_meridian(std::iter::empty()), 0.0);
    }

    #[test]
    fn single_point_returns_antipode() {
        // One vertex at 0°. The empty arc is the whole circle (360°)
        // with centre at 180°; central = antipode of cut = 0°.
        // Either pole works for a single point — accept either.
        let c = central_meridian([0.0]);
        assert!(c.abs() < 1e-6 || (c.abs() - 180.0).abs() < 1e-6, "got {c}");
    }

    #[test]
    fn nz_fiji_central_is_near_174_east() {
        // Samples covering NZ main + Chatham + Fiji (mod 360°).
        // NZ ~165–175°E, Chatham at ~−176° → 184°, Fiji ~177–183°.
        let lons = [165.0, 170.0, 175.0, 180.0, 184.0, 177.0, 183.0];
        let c = central_meridian(lons);
        assert!(
            (c - 174.5).abs() < 1.0,
            "expected ~174.5°E, got {c}"
        );
    }

    #[test]
    fn usa_with_aleutians_central_in_pacific() {
        // CONUS (-125° to -65°), Alaska (-168° to -141°), Aleutians
        // (after per-ring antimeridian normalize) at ~+175° to +185°.
        let lons = [-125.0, -100.0, -65.0, -168.0, -141.0, 175.0, 185.0];
        let c = central_meridian(lons);
        // Expect a Pacific-centric central meridian (negative, not far
        // from -120°). Check it's in the Americas/Pacific half.
        assert!(c < 0.0 && c > -180.0, "expected Pacific central, got {c}");
    }

    #[test]
    fn world_spanning_returns_low_magnitude() {
        // Uniformly-spaced vertices at every 30° → all gaps equal,
        // any could win. Just sanity-check the result is finite.
        let lons: Vec<f64> = (0..12).map(|i| i as f64 * 30.0).collect();
        let c = central_meridian(lons);
        assert!(c.is_finite());
        assert!((-180.0..=180.0).contains(&c));
    }

    #[test]
    fn rotate_lon_identity_when_close_to_central() {
        // Anything within ±180° of central is unchanged.
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
        // rotate_lon(rotate_lon(lon, c), -c) should map back near lon
        // (mod 360).
        for &lon in &[-179.0, -1.0, 0.0, 45.0, 174.5, 178.0] {
            for &c in &[-120.0, 0.0, 30.0, 174.5] {
                let r = rotate_lon(lon, c);
                // Difference from original should be a multiple of 360°.
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
        // A polygon with all vertices on one side of the world should
        // shift uniformly when rotated by a far-side central meridian.
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
        // Rotating by the same meridian (central = 172.5°, near the
        // polygon's centre) should leave coords essentially unchanged.
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
        // central = 174.5°E (NZ-Fiji frame). A polygon with vertices
        // near -176° should shift to +184°.
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

    #[test]
    fn collect_lons_polygon() {
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 1.0, lat: 0.0 },
                LonLat { lon: 2.0, lat: 0.0 },
            ],
            holes: vec![vec![LonLat { lon: 3.0, lat: 0.0 }]],
        };
        let mut out = Vec::new();
        collect_lons(&g, &mut out);
        assert_eq!(out, vec![1.0, 2.0, 3.0]);
    }

    #[test]
    fn collect_lons_multipolygon() {
        let g = Geometry::MultiPolygon(vec![
            Polygon {
                outer: vec![LonLat { lon: 1.0, lat: 0.0 }],
                holes: vec![],
            },
            Polygon {
                outer: vec![LonLat { lon: 5.0, lat: 0.0 }],
                holes: vec![],
            },
        ]);
        let mut out = Vec::new();
        collect_lons(&g, &mut out);
        assert_eq!(out, vec![1.0, 5.0]);
    }

    #[test]
    fn full_workflow_nz_fiji() {
        // Synthetic NZ South Island + Chatham + Fiji as separate polys.
        let nz = Polygon {
            outer: vec![
                LonLat { lon: 168.0, lat: -46.0 },
                LonLat { lon: 174.0, lat: -46.0 },
                LonLat { lon: 174.0, lat: -41.0 },
                LonLat { lon: 168.0, lat: -41.0 },
                LonLat { lon: 168.0, lat: -46.0 },
            ],
            holes: vec![],
        };
        let chatham = Polygon {
            outer: vec![
                LonLat { lon: -177.0, lat: -44.0 },
                LonLat { lon: -176.0, lat: -44.0 },
                LonLat { lon: -176.0, lat: -43.0 },
                LonLat { lon: -177.0, lat: -43.0 },
                LonLat { lon: -177.0, lat: -44.0 },
            ],
            holes: vec![],
        };
        let fiji = Polygon {
            outer: vec![
                LonLat { lon: 177.0, lat: -19.0 },
                LonLat { lon: 180.0, lat: -19.0 },
                LonLat { lon: 180.0, lat: -16.0 },
                LonLat { lon: 177.0, lat: -16.0 },
                LonLat { lon: 177.0, lat: -19.0 },
            ],
            holes: vec![],
        };
        let mut combined = Geometry::MultiPolygon(vec![nz, chatham, fiji]);

        // Compute central, rotate.
        let mut lons = Vec::new();
        collect_lons(&combined, &mut lons);
        let c = central_meridian(lons);
        rotate_geometry(&mut combined, c);

        // After rotation, all longitudes should fall in a tight band.
        let mut all = Vec::new();
        collect_lons(&combined, &mut all);
        let min = all.iter().cloned().fold(f64::INFINITY, f64::min);
        let max = all.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let span = max - min;
        assert!(
            span < 30.0,
            "expected tight (<30°) span after rotation, got {span}° (min={min}, max={max})"
        );
    }
}
