//! SVG composition for projected geometry.
//!
//! One `compose_layer` call produces a complete `<svg>` document for
//! a single layer. The styling (stroke, fill) is supplied by the
//! theme; this module only handles geometry-to-path conversion and
//! the document scaffold.

use crate::geometry::{Geometry, LonLat};
use crate::project::Projector;
use marki_core::escape_html as escape_attr;
use std::fmt::Write;

/// One renderable feature on a layer.
pub struct Feature<'a> {
    /// Geometry to draw.
    pub geom: &'a Geometry,
    /// Stylistic role this feature plays (`"outline"`, `"highlight"`,
    /// `"coast"`, `"neighbor"`, …). The theme maps each role to
    /// stroke/fill values.
    pub role: &'a str,
}

/// Per-layer styling resolved from the theme.
#[derive(Clone, Default)]
pub struct LayerStyle {
    pub background: Option<String>,
    pub roles: Vec<RoleStyle>,
}

#[derive(Clone)]
pub struct RoleStyle {
    pub role: String,
    pub fill: String,
    pub stroke: String,
    pub stroke_width: f64,
}

impl LayerStyle {
    pub fn role(&self, name: &str) -> Option<&RoleStyle> {
        self.roles.iter().find(|r| r.role == name)
    }
}

/// Render one layer to a self-contained SVG document.
pub fn compose_layer(
    width: u32,
    height: u32,
    style: &LayerStyle,
    projector: &dyn Projector,
    features: &[Feature<'_>],
) -> String {
    let mut out = String::with_capacity(4096);
    let _ = write!(
        out,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" \
         viewBox=\"0 0 {width} {height}\" \
         width=\"{width}\" height=\"{height}\">"
    );
    if let Some(bg) = &style.background {
        let _ = write!(
            out,
            "<rect width=\"{width}\" height=\"{height}\" fill=\"{}\"/>",
            escape_attr(bg)
        );
    }

    // Group features by role so we emit one <g> per styled bucket.
    let mut by_role: std::collections::BTreeMap<&str, Vec<&Feature<'_>>> =
        std::collections::BTreeMap::new();
    for f in features {
        by_role.entry(f.role).or_default().push(f);
    }
    // Render in a fixed stacking order: highlights always on top so
    // they aren't buried under opaque country/outline fills.
    let role_order: &[&str] = &["coast", "neighbor", "outline", "highlight"];
    let ordered_roles: Vec<&str> = role_order
        .iter()
        .copied()
        .filter(|r| by_role.contains_key(r))
        .chain(by_role.keys().copied().filter(|r| !role_order.contains(r)))
        .collect();
    for role in ordered_roles {
        let feats = &by_role[role];
        let role_style = style
            .role(role)
            .cloned()
            .unwrap_or_else(|| default_role_style(role));
        let _ = write!(
            out,
            "<g fill=\"{fill}\" stroke=\"{stroke}\" stroke-width=\"{sw}\" \
             stroke-linejoin=\"round\" stroke-linecap=\"round\">",
            fill = escape_attr(&role_style.fill),
            stroke = escape_attr(&role_style.stroke),
            sw = role_style.stroke_width,
        );
        for f in feats {
            write_feature(&mut out, projector, f.geom);
        }
        out.push_str("</g>");
    }

    out.push_str("</svg>");
    out
}

fn default_role_style(role: &str) -> RoleStyle {
    // Conservative defaults so a missing theme entry doesn't render
    // invisibly. Themes are expected to override.
    let (fill, stroke) = match role {
        "highlight" => ("#d33", "#900"),
        "outline" => ("#eee", "#333"),
        "neighbor" => ("#ddd", "#888"),
        "coast" => ("none", "#36b"),
        _ => ("none", "#000"),
    };
    RoleStyle {
        role: role.to_string(),
        fill: fill.to_string(),
        stroke: stroke.to_string(),
        stroke_width: 1.0,
    }
}

fn write_feature(out: &mut String, p: &dyn Projector, g: &Geometry) {
    match g {
        Geometry::Point(pt) => {
            let (x, y) = p.project(*pt);
            let _ = write!(out, "<circle cx=\"{x:.2}\" cy=\"{y:.2}\" r=\"2\"/>");
        }
        Geometry::LineString(line) => {
            let d = path_data_open(p, line);
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill=\"none\"/>");
            }
        }
        Geometry::MultiLineString(lines) => {
            let mut combined = String::new();
            for l in lines {
                let d = path_data_open(p, l);
                if !d.is_empty() {
                    if !combined.is_empty() {
                        combined.push(' ');
                    }
                    combined.push_str(&d);
                }
            }
            if !combined.is_empty() {
                let _ = write!(out, "<path d=\"{combined}\" fill=\"none\"/>");
            }
        }
        Geometry::Polygon { outer, holes } => {
            let mut d = path_data_closed(p, outer);
            for h in holes {
                d.push(' ');
                d.push_str(&path_data_closed(p, h));
            }
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill-rule=\"evenodd\"/>");
            }
        }
        Geometry::MultiPolygon(polys) => {
            let mut d = String::new();
            for poly in polys {
                if !d.is_empty() {
                    d.push(' ');
                }
                d.push_str(&path_data_closed(p, &poly.outer));
                for h in &poly.holes {
                    d.push(' ');
                    d.push_str(&path_data_closed(p, h));
                }
            }
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill-rule=\"evenodd\"/>");
            }
        }
    }
}

/// Sub-pixel simplification tolerance. Points that deviate less than
/// this many pixels from the simplified line are removed. Because
/// coordinates are in projected pixels, this auto-adapts to zoom:
/// a 600 px Germany keeps fine detail; a 600 px world map simplifies
/// aggressively. 1.0 px is imperceptible at card viewing distance.
const SIMPLIFY_EPSILON: f64 = 1.0;

fn path_data_open(p: &dyn Projector, pts: &[LonLat]) -> String {
    let projected: Vec<(f64, f64)> = pts.iter().map(|pt| p.project(*pt)).collect();
    let simplified = crate::simplify::simplify(&projected, SIMPLIFY_EPSILON);
    let mut s = String::with_capacity(simplified.len() * 12);
    let mut first = true;
    for &(x, y) in &simplified {
        if first {
            let _ = write!(s, "M{x:.2} {y:.2}");
            first = false;
        } else {
            let _ = write!(s, " L{x:.2} {y:.2}");
        }
    }
    s
}

fn path_data_closed(p: &dyn Projector, pts: &[LonLat]) -> String {
    let mut s = path_data_open(p, pts);
    if !s.is_empty() {
        s.push_str(" Z");
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geometry::BBox;
    use crate::project::Equirectangular;

    #[test]
    fn empty_layer_still_yields_svg() {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        let style = LayerStyle::default();
        let svg = compose_layer(100, 100, &style, &p, &[]);
        assert!(svg.contains("<svg"));
        assert!(svg.contains("</svg>"));
    }

    #[test]
    fn polygon_renders_as_path() {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 0.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 0.0 },
                LonLat { lon: 10.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 10.0 },
                LonLat { lon: 0.0, lat: 0.0 },
            ],
            holes: vec![],
        };
        let svg = compose_layer(
            100,
            100,
            &LayerStyle::default(),
            &p,
            &[Feature {
                geom: &g,
                role: "outline",
            }],
        );
        assert!(svg.contains("<path"), "{svg}");
        assert!(svg.contains("M"), "{svg}");
        assert!(svg.contains("Z"), "{svg}");
    }

    #[test]
    fn role_style_lookup() {
        let s = LayerStyle {
            background: None,
            roles: vec![RoleStyle {
                role: "highlight".into(),
                fill: "#abc".into(),
                stroke: "#000".into(),
                stroke_width: 2.0,
            }],
        };
        assert!(s.role("highlight").is_some());
        assert!(s.role("missing").is_none());
    }
}
