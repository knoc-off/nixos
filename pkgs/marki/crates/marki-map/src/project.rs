//! Lon/lat → SVG-pixel projection.
//!
//! For milestone 1 we hand-roll two projections:
//!
//!   * `Equirectangular` — `(lon, lat)` map directly to `(x, y)`. The
//!     simplest possible projection; fine for small regions and
//!     country outlines where shape distortion at moderate latitudes
//!     is acceptable.
//!   * `Mercator` — Web Mercator (EPSG:3857) without the spherical
//!     correction — i.e. `y = ln(tan(π/4 + lat/2))`. Standard for
//!     world / continent views.
//!
//! Both projections "auto-fit" — they're constructed from a target
//! bbox and an output `(width, height)` and produce SVG-pixel
//! coordinates with the bbox occupying as much of the canvas as
//! possible while preserving aspect ratio. The canvas is centered.

use crate::geometry::{BBox, LonLat};

/// Lon/lat (degrees) → SVG-pixel coordinates.
pub trait Projector {
    /// Project a point. Result is in SVG units (pixel coordinates,
    /// origin top-left, y axis pointing down).
    fn project(&self, p: LonLat) -> (f64, f64);
}

/// Auto-fit equirectangular projection.
pub struct Equirectangular {
    pub bbox: BBox,
    /// Output canvas size, pixels.
    pub size: (f64, f64),
    /// Per-axis scale (px per degree). Equal on both axes (we pick the
    /// smaller to preserve aspect ratio); precomputed.
    scale: f64,
    /// Pixel offsets so the bbox is centered.
    offset_x: f64,
    offset_y: f64,
}

impl Equirectangular {
    pub fn fit(bbox: BBox, size: (f64, f64)) -> Self {
        let (w, h) = size;
        let dx = (bbox.max_lon - bbox.min_lon).max(1e-9);
        let dy = (bbox.max_lat - bbox.min_lat).max(1e-9);
        let sx = w / dx;
        let sy = h / dy;
        let scale = sx.min(sy);
        let used_w = dx * scale;
        let used_h = dy * scale;
        let offset_x = (w - used_w) * 0.5;
        let offset_y = (h - used_h) * 0.5;
        Self {
            bbox,
            size,
            scale,
            offset_x,
            offset_y,
        }
    }
}

impl Projector for Equirectangular {
    fn project(&self, p: LonLat) -> (f64, f64) {
        let x = self.offset_x + (p.lon - self.bbox.min_lon) * self.scale;
        // Y axis flipped: SVG +y goes down, latitude goes up.
        let y =
            self.offset_y + (self.bbox.max_lat - p.lat) * self.scale;
        (x, y)
    }
}

/// Auto-fit Web Mercator (spherical Mercator). Latitude is clamped to
/// ±85.05113° to avoid the projection's pole singularity.
pub struct Mercator {
    /// Source bbox in lon/lat degrees.
    pub bbox: BBox,
    pub size: (f64, f64),
    /// Mercator-projected bbox, used to scale.
    proj_bbox: ProjBBox,
    scale: f64,
    offset_x: f64,
    offset_y: f64,
}

#[derive(Clone, Copy)]
struct ProjBBox {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
}

const MERC_MAX_LAT: f64 = 85.051_128_779_807;

pub fn mercator_y(lat_deg: f64) -> f64 {
    let lat = lat_deg.clamp(-MERC_MAX_LAT, MERC_MAX_LAT).to_radians();
    (std::f64::consts::FRAC_PI_4 + lat * 0.5).tan().ln()
}

fn mercator_xy(p: LonLat) -> (f64, f64) {
    (p.lon.to_radians(), mercator_y(p.lat))
}

impl Mercator {
    pub fn fit(bbox: BBox, size: (f64, f64)) -> Self {
        let (w, h) = size;
        let p_min = mercator_xy(LonLat {
            lon: bbox.min_lon,
            lat: bbox.min_lat,
        });
        let p_max = mercator_xy(LonLat {
            lon: bbox.max_lon,
            lat: bbox.max_lat,
        });
        let proj_bbox = ProjBBox {
            min_x: p_min.0,
            min_y: p_min.1,
            max_x: p_max.0,
            max_y: p_max.1,
        };
        let dx = (proj_bbox.max_x - proj_bbox.min_x).max(1e-12);
        let dy = (proj_bbox.max_y - proj_bbox.min_y).max(1e-12);
        let scale = (w / dx).min(h / dy);
        let used_w = dx * scale;
        let used_h = dy * scale;
        let offset_x = (w - used_w) * 0.5;
        let offset_y = (h - used_h) * 0.5;
        Self {
            bbox,
            size,
            proj_bbox,
            scale,
            offset_x,
            offset_y,
        }
    }

    /// Aspect ratio (`projected_dx / projected_dy`) of `bbox` after
    /// Mercator projection. Used by the pipeline to size the canvas to
    /// match the data instead of letterboxing inside `spec.size`.
    pub fn projected_aspect(bbox: BBox) -> f64 {
        let p_min = mercator_xy(LonLat {
            lon: bbox.min_lon,
            lat: bbox.min_lat,
        });
        let p_max = mercator_xy(LonLat {
            lon: bbox.max_lon,
            lat: bbox.max_lat,
        });
        let dx = (p_max.0 - p_min.0).max(1e-12);
        let dy = (p_max.1 - p_min.1).max(1e-12);
        dx / dy
    }
}

impl Projector for Mercator {
    fn project(&self, p: LonLat) -> (f64, f64) {
        let (mx, my) = mercator_xy(p);
        let x = self.offset_x + (mx - self.proj_bbox.min_x) * self.scale;
        // Y flipped.
        let y = self.offset_y + (self.proj_bbox.max_y - my) * self.scale;
        (x, y)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn equirect_corners_land_on_canvas_edges() {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        let tl = p.project(LonLat { lon: 0.0, lat: 10.0 });
        let br = p.project(LonLat { lon: 10.0, lat: 0.0 });
        assert!((tl.0 - 0.0).abs() < 1e-6, "tl.x = {}", tl.0);
        assert!((tl.1 - 0.0).abs() < 1e-6, "tl.y = {}", tl.1);
        assert!((br.0 - 100.0).abs() < 1e-6, "br.x = {}", br.0);
        assert!((br.1 - 100.0).abs() < 1e-6, "br.y = {}", br.1);
    }

    #[test]
    fn equirect_letterboxes_when_aspect_mismatches() {
        // Tall canvas, square bbox. Should letterbox vertically.
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 200.0));
        let center = p.project(LonLat { lon: 5.0, lat: 5.0 });
        // Center lon/lat lands at canvas center.
        assert!((center.0 - 50.0).abs() < 1e-6);
        assert!((center.1 - 100.0).abs() < 1e-6);
    }

    #[test]
    fn mercator_corners_within_canvas() {
        let bb = BBox {
            min_lon: -10.0,
            min_lat: 35.0,
            max_lon: 15.0,
            max_lat: 60.0,
        };
        let p = Mercator::fit(bb, (600.0, 400.0));
        let tl = p.project(LonLat {
            lon: bb.min_lon,
            lat: bb.max_lat,
        });
        let br = p.project(LonLat {
            lon: bb.max_lon,
            lat: bb.min_lat,
        });
        assert!(tl.0 >= 0.0 && tl.0 <= 600.0);
        assert!(tl.1 >= 0.0 && tl.1 <= 400.0);
        assert!(br.0 >= 0.0 && br.0 <= 600.0);
        assert!(br.1 >= 0.0 && br.1 <= 400.0);
        // Top-left should map roughly to top-left.
        assert!(tl.1 < br.1);
        assert!(tl.0 < br.0);
    }

    #[test]
    fn mercator_aspect_germany_is_taller_than_wide() {
        // Germany's lon span ~10° (5.87 → 15.04), lat span ~9° (47.27 →
        // 55.06). Equirectangular would yield aspect ≈ 1.18 (slightly
        // wider than tall). Under Mercator at ~51°N, the projected dx
        // is unchanged but dy is stretched, so the aspect must be
        // *less than* the equirectangular value — we want it well
        // below 1.0 (taller than wide is the visually correct outcome
        // for a 51°N region of roughly equal degree extents).
        let germany = BBox {
            min_lon: 5.87,
            min_lat: 47.27,
            max_lon: 15.04,
            max_lat: 55.06,
        };
        let aspect = Mercator::projected_aspect(germany);
        let equirect_aspect =
            (germany.max_lon - germany.min_lon) / (germany.max_lat - germany.min_lat);
        assert!(
            aspect < equirect_aspect,
            "mercator aspect {aspect} not less than equirect {equirect_aspect}"
        );
        assert!(aspect < 1.0, "expected germany taller than wide, got {aspect}");
    }
}
