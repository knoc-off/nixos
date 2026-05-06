//! Internal lon/lat geometry types.
//!
//! The shapefile crate gives us its own geometry types but we wrap them
//! to insulate the rest of the pipeline from any one source format.
//! Coordinates are always (lon, lat) WGS84.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LonLat {
    pub lon: f64,
    pub lat: f64,
}

#[derive(Debug, Clone)]
pub enum Geometry {
    /// Single point.
    Point(LonLat),
    /// Open or closed polyline (e.g. coastline segment).
    LineString(Vec<LonLat>),
    /// Polygon, with one outer ring and zero or more inner (hole) rings.
    /// All rings are closed (first == last).
    Polygon {
        outer: Vec<LonLat>,
        holes: Vec<Vec<LonLat>>,
    },
    /// Multi-polygon — used for countries with islands etc.
    MultiPolygon(Vec<Polygon>),
    /// Multi-line — coastline data is naturally a collection.
    MultiLineString(Vec<Vec<LonLat>>),
}

impl Default for Geometry {
    /// Empty multi-polygon. Used as a placeholder for `mem::take` /
    /// `mem::replace` when transforming a `Vec<Geometry>` in place.
    fn default() -> Self {
        Geometry::MultiPolygon(Vec::new())
    }
}

#[derive(Debug, Clone)]
pub struct Polygon {
    pub outer: Vec<LonLat>,
    pub holes: Vec<Vec<LonLat>>,
}

#[derive(Debug, Clone, Copy)]
pub struct BBox {
    pub min_lon: f64,
    pub min_lat: f64,
    pub max_lon: f64,
    pub max_lat: f64,
}

impl BBox {
    pub fn empty() -> Self {
        Self {
            min_lon: f64::INFINITY,
            min_lat: f64::INFINITY,
            max_lon: f64::NEG_INFINITY,
            max_lat: f64::NEG_INFINITY,
        }
    }

    pub fn is_empty(&self) -> bool {
        !(self.min_lon.is_finite() && self.max_lon > self.min_lon)
    }

    pub fn extend_point(&mut self, p: LonLat) {
        if p.lon < self.min_lon {
            self.min_lon = p.lon;
        }
        if p.lat < self.min_lat {
            self.min_lat = p.lat;
        }
        if p.lon > self.max_lon {
            self.max_lon = p.lon;
        }
        if p.lat > self.max_lat {
            self.max_lat = p.lat;
        }
    }

    pub fn extend(&mut self, other: BBox) {
        if other.is_empty() {
            return;
        }
        if other.min_lon < self.min_lon {
            self.min_lon = other.min_lon;
        }
        if other.min_lat < self.min_lat {
            self.min_lat = other.min_lat;
        }
        if other.max_lon > self.max_lon {
            self.max_lon = other.max_lon;
        }
        if other.max_lat > self.max_lat {
            self.max_lat = other.max_lat;
        }
    }

    /// Pad each side by `frac` of the bbox size. `frac=0.05` adds 5%.
    pub fn padded(&self, frac: f64) -> BBox {
        let dx = (self.max_lon - self.min_lon) * frac;
        let dy = (self.max_lat - self.min_lat) * frac;
        BBox {
            min_lon: self.min_lon - dx,
            min_lat: self.min_lat - dy,
            max_lon: self.max_lon + dx,
            max_lat: self.max_lat + dy,
        }
    }

    pub fn intersects(&self, other: &BBox) -> bool {
        !(self.max_lon < other.min_lon
            || other.max_lon < self.min_lon
            || self.max_lat < other.min_lat
            || other.max_lat < self.min_lat)
    }
}

/// Compute the axis-aligned bounding box of a ring (slice of LonLat points).
pub fn ring_bbox(ring: &[LonLat]) -> BBox {
    let mut bb = BBox::empty();
    for p in ring {
        bb.extend_point(*p);
    }
    bb
}

/// Find the smallest-area outer polygon whose bbox fully contains `inner`'s
/// bbox. Used to reassign holes to the correct outer fragment after a split.
/// Returns `None` if no polygon encloses the inner ring.
pub fn best_outer_for(inner: &[LonLat], polys: &[Polygon]) -> Option<usize> {
    let inner_bb = ring_bbox(inner);
    let mut best: Option<(usize, f64)> = None;
    for (i, p) in polys.iter().enumerate() {
        let outer_bb = ring_bbox(&p.outer);
        if outer_bb.min_lon <= inner_bb.min_lon
            && outer_bb.min_lat <= inner_bb.min_lat
            && outer_bb.max_lon >= inner_bb.max_lon
            && outer_bb.max_lat >= inner_bb.max_lat
        {
            let area =
                (outer_bb.max_lon - outer_bb.min_lon) * (outer_bb.max_lat - outer_bb.min_lat);
            match best {
                None => best = Some((i, area)),
                Some((_, prev)) if area < prev => best = Some((i, area)),
                _ => {}
            }
        }
    }
    best.map(|(i, _)| i)
}

impl Geometry {
    pub fn bbox(&self) -> BBox {
        let mut bb = BBox::empty();
        match self {
            Geometry::Point(p) => bb.extend_point(*p),
            Geometry::LineString(pts) => {
                for p in pts {
                    bb.extend_point(*p);
                }
            }
            Geometry::Polygon { outer, .. } => {
                for p in outer {
                    bb.extend_point(*p);
                }
            }
            Geometry::MultiPolygon(polys) => {
                for poly in polys {
                    for p in &poly.outer {
                        bb.extend_point(*p);
                    }
                }
            }
            Geometry::MultiLineString(lines) => {
                for line in lines {
                    for p in line {
                        bb.extend_point(*p);
                    }
                }
            }
        }
        bb
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bbox_extend() {
        let mut b = BBox::empty();
        assert!(b.is_empty());
        b.extend_point(LonLat { lon: 1.0, lat: 2.0 });
        b.extend_point(LonLat { lon: -1.0, lat: 5.0 });
        assert!((b.min_lon - -1.0).abs() < 1e-9);
        assert!((b.max_lat - 5.0).abs() < 1e-9);
        assert!(!b.is_empty());
    }

    #[test]
    fn polygon_bbox_uses_outer_ring() {
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
        let bb = g.bbox();
        assert_eq!(bb.min_lon, 0.0);
        assert_eq!(bb.max_lon, 10.0);
        assert_eq!(bb.min_lat, 0.0);
        assert_eq!(bb.max_lat, 5.0);
    }

    #[test]
    fn bbox_intersection() {
        let a = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let b = BBox {
            min_lon: 5.0,
            min_lat: 5.0,
            max_lon: 15.0,
            max_lat: 15.0,
        };
        let c = BBox {
            min_lon: 20.0,
            min_lat: 20.0,
            max_lon: 30.0,
            max_lat: 30.0,
        };
        assert!(a.intersects(&b));
        assert!(!a.intersects(&c));
    }
}
