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
    /// Render faithfully: skip per-feature simplification and island
    /// culling. Set for composites (continent / subregion / neighbours)
    /// whose member units share coincident borders — decimating each
    /// independently would split those borders into double lines and
    /// culling would drop small member countries.
    pub faithful: bool,
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

/// Detail-reduction knobs for one compose pass, in rendered pixels.
#[derive(Clone, Copy)]
pub struct RenderDetail {
    /// Minimum projected area, in px², below which a polygon component
    /// is a candidate for culling. The threshold is `min_island_px²`.
    /// `0.0` disables culling.
    pub min_island_px2: f64,
    /// Relative-size escape hatch: a component whose area is at least
    /// this fraction of the feature's largest component is kept even
    /// when below `min_island_px2`.
    pub island_rel_frac: f64,
    /// Douglas-Peucker simplification tolerance in px. `0.0` disables.
    pub simplify_px: f64,
}

impl RenderDetail {
    /// Detail settings for a faithful render: no culling and no
    /// simplification, so coincident borders between adjacent units stay
    /// exactly coincident. Used for composite features.
    fn faithful() -> Self {
        Self {
            min_island_px2: 0.0,
            island_rel_frac: 0.0,
            simplify_px: 0.0,
        }
    }
}

impl Default for RenderDetail {
    /// No culling, 1 px simplification — the historical behaviour, used
    /// by tests that don't exercise detail reduction.
    fn default() -> Self {
        Self {
            min_island_px2: 0.0,
            island_rel_frac: 0.0,
            simplify_px: 1.0,
        }
    }
}

/// Render one layer to a self-contained SVG document.
///
/// Features whose role is `"hull"` are not drawn as outlines: each is
/// wrapped in a rounded convex hull — the convex hull of the feature's
/// vertices, expanded outward by `hull_radius_px` with rounded corners
/// (the Minkowski sum of the hull with a disk). This encloses the
/// feature's entire extent (e.g. every island of an archipelago) in one
/// smooth, padded region. `hull_radius_px` (in SVG pixels) is the corner
/// radius / outward padding; it is ignored for every other role and may
/// be `0.0` on non-hull layers.
///
/// `detail` controls per-feature small-landmass culling and outline
/// simplification (see [`RenderDetail`]); culling never touches the
/// hull, which always wraps the feature's full extent.
pub fn compose_layer(
    width: u32,
    height: u32,
    style: &LayerStyle,
    projector: &dyn Projector,
    features: &[Feature<'_>],
    hull_radius_px: f64,
    detail: RenderDetail,
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
            if role == "hull" {
                write_hull(&mut out, projector, f.geom, hull_radius_px);
            } else {
                let fdetail = if f.faithful {
                    RenderDetail::faithful()
                } else {
                    detail
                };
                write_feature(&mut out, projector, f.geom, fdetail);
            }
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
        "hull" => ("#d33a", "#900a"),
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

/// Wrap a feature in a rounded convex hull, sized by `radius_px`.
///
/// Computes the convex hull of the feature's projected vertices and
/// emits its outward offset (Minkowski sum with a disk of radius
/// `radius_px`): straight offset edges joined by corner arcs. Degenerate
/// inputs fall back gracefully — a single point becomes a circle, two
/// points a capsule — so genuinely tiny specks still get a visible halo.
fn write_hull(out: &mut String, p: &dyn Projector, g: &Geometry, radius_px: f64) {
    let pts = gather_projected_vertices(p, g);
    let hull = convex_hull(&pts);
    write_rounded_hull(out, &hull, radius_px);
}

/// Project every outer-ring vertex of a geometry's polygon components.
/// Returns an empty vec for geometries with no polygon area (points,
/// lines) — hull halos only make sense for areal features.
fn gather_projected_vertices(p: &dyn Projector, g: &Geometry) -> Vec<(f64, f64)> {
    let mut pts = Vec::new();
    let mut add_ring = |ring: &[LonLat]| {
        pts.extend(ring.iter().map(|pt| p.project(*pt)));
    };
    match g {
        Geometry::Polygon { outer, .. } => add_ring(outer),
        Geometry::MultiPolygon(polys) => {
            for poly in polys {
                add_ring(&poly.outer);
            }
        }
        _ => {}
    }
    pts
}

/// Convex hull of a point set via Andrew's monotone chain, O(n log n).
/// Output is the hull vertices in counter-clockwise order (in standard
/// math axes; note SVG y points down, so this reads clockwise on screen)
/// without the closing duplicate. Returns the input (deduplicated) when
/// fewer than three distinct points are given.
fn convex_hull(points: &[(f64, f64)]) -> Vec<(f64, f64)> {
    let mut pts: Vec<(f64, f64)> = points.to_vec();
    pts.sort_by(|a, b| {
        a.0.partial_cmp(&b.0)
            .unwrap()
            .then(a.1.partial_cmp(&b.1).unwrap())
    });
    pts.dedup();
    if pts.len() < 3 {
        return pts;
    }
    // Cross product of OA × OB; > 0 means counter-clockwise turn.
    let cross = |o: (f64, f64), a: (f64, f64), b: (f64, f64)| {
        (a.0 - o.0) * (b.1 - o.1) - (a.1 - o.1) * (b.0 - o.0)
    };
    let mut hull: Vec<(f64, f64)> = Vec::with_capacity(pts.len() + 1);
    // Lower hull.
    for &pt in &pts {
        while hull.len() >= 2
            && cross(hull[hull.len() - 2], hull[hull.len() - 1], pt) <= 0.0
        {
            hull.pop();
        }
        hull.push(pt);
    }
    // Upper hull.
    let lower_len = hull.len() + 1;
    for &pt in pts.iter().rev() {
        while hull.len() >= lower_len
            && cross(hull[hull.len() - 2], hull[hull.len() - 1], pt) <= 0.0
        {
            hull.pop();
        }
        hull.push(pt);
    }
    hull.pop(); // last point equals the first
    hull
}

/// Emit the outward offset of a convex hull as an SVG path: each edge is
/// pushed out by `pad` along its outward normal, and consecutive offset
/// edges are joined by a circular arc of radius `pad` centered on the
/// original hull vertex. Degenerate hulls fall back to a circle (one
/// point) or a capsule (two points).
fn write_rounded_hull(out: &mut String, hull: &[(f64, f64)], pad: f64) {
    let pad = pad.max(0.0);
    match hull.len() {
        0 => {}
        1 => {
            let (x, y) = hull[0];
            let _ = write!(out, "<circle cx=\"{x:.2}\" cy=\"{y:.2}\" r=\"{pad:.2}\"/>");
        }
        2 => write_capsule(out, hull[0], hull[1], pad),
        _ => {
            if pad <= 0.0 {
                // No padding: just stroke the bare hull polygon.
                let mut d = String::new();
                for (i, &(x, y)) in hull.iter().enumerate() {
                    let _ = write!(d, "{}{x:.2} {y:.2}", if i == 0 { "M" } else { " L" });
                }
                d.push_str(" Z");
                let _ = write!(out, "<path d=\"{d}\"/>");
                return;
            }
            write_rounded_polygon(out, hull, pad);
        }
    }
}

/// Outward-offset path for a convex polygon with >= 3 vertices. Orients
/// the hull clockwise in screen space so the offset normal (a 90° turn)
/// always points outward, then walks the vertices emitting offset edge
/// endpoints connected by corner arcs.
fn write_rounded_polygon(out: &mut String, hull: &[(f64, f64)], pad: f64) {
    // Signed area (shoelace) in screen coordinates. Positive here means
    // clockwise on screen (y-down); flip to a known orientation so the
    // outward normal is consistent.
    let mut area2 = 0.0;
    for i in 0..hull.len() {
        let (x0, y0) = hull[i];
        let (x1, y1) = hull[(i + 1) % hull.len()];
        area2 += x0 * y1 - x1 * y0;
    }
    let mut poly: Vec<(f64, f64)> = hull.to_vec();
    if area2 < 0.0 {
        poly.reverse();
    }
    // With clockwise (on-screen) winding, the outward normal of edge
    // (a -> b) is the edge direction rotated +90°: (dy, -dx) normalized.
    let n = poly.len();
    let mut d = String::new();
    for i in 0..n {
        let a = poly[i];
        let b = poly[(i + 1) % n];
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let len = (dx * dx + dy * dy).sqrt();
        if len < 1e-9 {
            continue;
        }
        let (nx, ny) = (dy / len, -dx / len);
        let a_off = (a.0 + nx * pad, a.1 + ny * pad);
        let b_off = (b.0 + nx * pad, b.1 + ny * pad);
        if d.is_empty() {
            let _ = write!(d, "M{:.2} {:.2}", a_off.0, a_off.1);
        } else {
            // Arc around vertex `a` from the previous edge's offset end
            // to this edge's offset start. sweep-flag 1 = clockwise.
            let _ = write!(
                d,
                " A{pad:.2} {pad:.2} 0 0 1 {:.2} {:.2}",
                a_off.0, a_off.1
            );
        }
        let _ = write!(d, " L{:.2} {:.2}", b_off.0, b_off.1);
    }
    // Closing arc around the first vertex.
    let first = poly[0];
    let last_edge = poly[n - 1];
    let (dx, dy) = (first.0 - last_edge.0, first.1 - last_edge.1);
    let len = (dx * dx + dy * dy).sqrt();
    if len >= 1e-9 {
        let (nx, ny) = (dy / len, -dx / len);
        let start = (first.0 + nx * pad, first.1 + ny * pad);
        let _ = write!(d, " A{pad:.2} {pad:.2} 0 0 1 {:.2} {:.2}", start.0, start.1);
    }
    d.push_str(" Z");
    let _ = write!(out, "<path d=\"{d}\"/>");
}

/// Stadium/capsule outline around the segment a–b, offset by `pad` on
/// both sides with semicircular caps.
fn write_capsule(out: &mut String, a: (f64, f64), b: (f64, f64), pad: f64) {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let len = (dx * dx + dy * dy).sqrt();
    if len < 1e-9 {
        let _ = write!(out, "<circle cx=\"{:.2}\" cy=\"{:.2}\" r=\"{pad:.2}\"/>", a.0, a.1);
        return;
    }
    let (nx, ny) = (dy / len * pad, -dx / len * pad);
    // Offset endpoints on the +normal side and -normal side.
    let a1 = (a.0 + nx, a.1 + ny);
    let b1 = (b.0 + nx, b.1 + ny);
    let b2 = (b.0 - nx, b.1 - ny);
    let a2 = (a.0 - nx, a.1 - ny);
    let _ = write!(
        out,
        "<path d=\"M{:.2} {:.2} L{:.2} {:.2} A{pad:.2} {pad:.2} 0 0 1 {:.2} {:.2} \
         L{:.2} {:.2} A{pad:.2} {pad:.2} 0 0 1 {:.2} {:.2} Z\"/>",
        a1.0, a1.1, b1.0, b1.1, b2.0, b2.1, a2.0, a2.1, a1.0, a1.1
    );
}

fn write_feature(out: &mut String, p: &dyn Projector, g: &Geometry, detail: RenderDetail) {
    let eps = detail.simplify_px;
    match g {
        Geometry::Point(pt) => {
            let (x, y) = p.project(*pt);
            let _ = write!(out, "<circle cx=\"{x:.2}\" cy=\"{y:.2}\" r=\"2\"/>");
        }
        Geometry::LineString(line) => {
            let d = path_data_open(p, line, eps);
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill=\"none\"/>");
            }
        }
        Geometry::MultiLineString(lines) => {
            let mut combined = String::new();
            for l in lines {
                let d = path_data_open(p, l, eps);
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
            // A single component is the whole feature — never culled.
            let mut d = path_data_closed(p, outer, eps);
            for h in holes {
                if !keep_hole(p, h, detail) {
                    continue;
                }
                let hd = path_data_closed(p, h, eps);
                if !hd.is_empty() {
                    d.push(' ');
                    d.push_str(&hd);
                }
            }
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill-rule=\"evenodd\"/>");
            }
        }
        Geometry::MultiPolygon(polys) => {
            let keep = cull_components(p, polys, detail);
            let mut d = String::new();
            for (poly, keep_it) in polys.iter().zip(keep) {
                if !keep_it {
                    continue;
                }
                let outer = path_data_closed(p, &poly.outer, eps);
                if outer.is_empty() {
                    continue;
                }
                if !d.is_empty() {
                    d.push(' ');
                }
                d.push_str(&outer);
                for h in &poly.holes {
                    if !keep_hole(p, h, detail) {
                        continue;
                    }
                    let hd = path_data_closed(p, h, eps);
                    if !hd.is_empty() {
                        d.push(' ');
                        d.push_str(&hd);
                    }
                }
            }
            if !d.is_empty() {
                let _ = write!(out, "<path d=\"{d}\" fill-rule=\"evenodd\"/>");
            }
        }
    }
}

/// Keep a hole only if it encloses a visible area. Tiny holes (sliver
/// artifacts in the source boundaries, or specks left over from a
/// boolean union) below `min_island_px²` are dropped so they don't
/// render as pinprick notches. Culling is skipped when the threshold is
/// zero, so unculled renders (`min_island_px = 0`) keep every hole.
fn keep_hole(p: &dyn Projector, hole: &[LonLat], detail: RenderDetail) -> bool {
    detail.min_island_px2 <= 0.0 || projected_ring_area(p, hole) >= detail.min_island_px2
}

/// Decide which components of a multipolygon survive detail culling.
///
/// Returns one flag per input polygon. The largest component is always
/// kept so a feature never fully vanishes (a tiny island that is itself
/// the answer survives even zoomed far out). Every other component
/// survives if it is individually visible (`area ≥ min_island_px²`) or
/// comparable to the feature's largest mass (`area ≥ rel_frac × max`),
/// so clusters of roughly equal islands stay intact while sub-pixel
/// specks beside one dominant landmass are dropped. Culling is skipped
/// entirely when `min_island_px²` is zero or the feature has ≤1 part.
fn cull_components(p: &dyn Projector, polys: &[crate::geometry::Polygon], detail: RenderDetail) -> Vec<bool> {
    let n = polys.len();
    if n <= 1 || detail.min_island_px2 <= 0.0 {
        return vec![true; n];
    }
    let areas: Vec<f64> = polys
        .iter()
        .map(|poly| projected_ring_area(p, &poly.outer))
        .collect();
    let mut max_idx = 0;
    let mut max_area = 0.0;
    for (i, &a) in areas.iter().enumerate() {
        if a > max_area {
            max_area = a;
            max_idx = i;
        }
    }
    let rel_thresh = detail.island_rel_frac * max_area;
    areas
        .iter()
        .enumerate()
        .map(|(i, &a)| i == max_idx || a >= detail.min_island_px2 || a >= rel_thresh)
        .collect()
}

/// Unsigned area of a ring in projected (pixel) space via the shoelace
/// formula. Rings with fewer than three points have zero area.
fn projected_ring_area(p: &dyn Projector, ring: &[LonLat]) -> f64 {
    if ring.len() < 3 {
        return 0.0;
    }
    let pts: Vec<(f64, f64)> = ring.iter().map(|pt| p.project(*pt)).collect();
    let mut a2 = 0.0;
    for i in 0..pts.len() {
        let (x0, y0) = pts[i];
        let (x1, y1) = pts[(i + 1) % pts.len()];
        a2 += x0 * y1 - x1 * y0;
    }
    (a2 * 0.5).abs()
}

/// Project and simplify a ring/line into screen-space points.
fn project_simplify(p: &dyn Projector, pts: &[LonLat], eps: f64) -> Vec<(f64, f64)> {
    let projected: Vec<(f64, f64)> = pts.iter().map(|pt| p.project(*pt)).collect();
    crate::simplify::simplify(&projected, eps)
}

/// Serialize projected points to an SVG `M/L` path fragment (no close).
fn points_to_path(simplified: &[(f64, f64)]) -> String {
    let mut s = String::with_capacity(simplified.len() * 12);
    let mut first = true;
    for &(x, y) in simplified {
        if first {
            let _ = write!(s, "M{x:.2} {y:.2}");
            first = false;
        } else {
            let _ = write!(s, " L{x:.2} {y:.2}");
        }
    }
    s
}

/// Count points that remain distinct at the 2-decimal precision we emit.
/// A closed ring with fewer than three such vertices encloses no visible
/// area and would render as a stray dot or hairline.
fn distinct_points(simplified: &[(f64, f64)]) -> usize {
    let mut v: Vec<(i64, i64)> = simplified
        .iter()
        .map(|&(x, y)| ((x * 100.0).round() as i64, (y * 100.0).round() as i64))
        .collect();
    v.sort_unstable();
    v.dedup();
    v.len()
}

fn path_data_open(p: &dyn Projector, pts: &[LonLat], eps: f64) -> String {
    points_to_path(&project_simplify(p, pts, eps))
}

fn path_data_closed(p: &dyn Projector, pts: &[LonLat], eps: f64) -> String {
    let simplified = project_simplify(p, pts, eps);
    // Drop rings that collapse below a triangle: a sliver hole or speck
    // that simplifies to one or two distinct pixels is just visual noise
    // (the "dotted" artifact from messy source boundaries).
    if distinct_points(&simplified) < 3 {
        return String::new();
    }
    let mut s = points_to_path(&simplified);
    s.push_str(" Z");
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
        let svg = compose_layer(100, 100, &style, &p, &[], 0.0, RenderDetail::default());
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
                faithful: false,
            }],
            0.0,
            RenderDetail::default(),
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

    #[test]
    fn hull_feature_wraps_extent_with_rounded_path() {
        // 0–10° square on a 100×100 equirect canvas projects to the full
        // canvas square. The hull is that square, offset outward by the
        // padding with rounded corners — a <path>, not a centroid dot.
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
            &[Feature { geom: &g, role: "hull", faithful: false }],
            12.0,
            RenderDetail::default(),
        );
        assert!(svg.contains("<path"), "hull must draw a path: {svg}");
        assert!(!svg.contains("<circle"), "extended hull is not a circle: {svg}");
        assert!(svg.contains("A12.00 12.00"), "corner arcs at pad radius: {svg}");
        // Offset reaches 12px beyond the 0..100 square on every side.
        assert!(svg.contains("112.00"), "padded past max edge: {svg}");
        assert!(svg.contains("-12.00"), "padded past min edge: {svg}");
    }

    #[test]
    fn hull_wraps_multiple_islands_in_one_region() {
        // Two far-apart squares (an "archipelago") share a single hull
        // that encloses both, not one blob each.
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 100.0,
            max_lat: 100.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        let square = |x: f64, y: f64| crate::geometry::Polygon {
            outer: vec![
                LonLat { lon: x, lat: y },
                LonLat { lon: x + 5.0, lat: y },
                LonLat { lon: x + 5.0, lat: y + 5.0 },
                LonLat { lon: x, lat: y + 5.0 },
            ],
            holes: vec![],
        };
        let g = Geometry::MultiPolygon(vec![square(0.0, 0.0), square(90.0, 90.0)]);
        let svg = compose_layer(
            100,
            100,
            &LayerStyle::default(),
            &p,
            &[Feature { geom: &g, role: "hull", faithful: false }],
            4.0,
            RenderDetail::default(),
        );
        // A single closed path spanning both corners of the canvas.
        assert_eq!(svg.matches("<path").count(), 1, "one combined hull: {svg}");
        assert!(svg.contains("A4.00 4.00"), "rounded corners: {svg}");
    }

    #[test]
    fn hull_degenerates_to_circle_for_single_point() {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        // A polygon collapsed to a single coordinate → 1-point hull.
        let g = Geometry::Polygon {
            outer: vec![
                LonLat { lon: 5.0, lat: 5.0 },
                LonLat { lon: 5.0, lat: 5.0 },
                LonLat { lon: 5.0, lat: 5.0 },
            ],
            holes: vec![],
        };
        let svg = compose_layer(
            100,
            100,
            &LayerStyle::default(),
            &p,
            &[Feature { geom: &g, role: "hull", faithful: false }],
            12.0,
            RenderDetail::default(),
        );
        assert!(svg.contains("<circle"), "single point → circle: {svg}");
        assert!(svg.contains("r=\"12.00\""), "{svg}");
    }

    #[test]
    fn hull_skips_line_geometry() {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 10.0,
            max_lat: 10.0,
        };
        let p = Equirectangular::fit(bb, (100.0, 100.0));
        let g = Geometry::LineString(vec![
            LonLat { lon: 0.0, lat: 0.0 },
            LonLat { lon: 10.0, lat: 10.0 },
        ]);
        let svg = compose_layer(
            100,
            100,
            &LayerStyle::default(),
            &p,
            &[Feature { geom: &g, role: "hull", faithful: false }],
            12.0,
            RenderDetail::default(),
        );
        assert!(!svg.contains("<circle"), "no area → no halo: {svg}");
        // The hull <g> wrapper is the only path-free path-less group.
        assert!(
            !svg.contains("A12.00"),
            "no hull arcs for a bare line: {svg}"
        );
    }

    #[test]
    fn convex_hull_of_square_with_interior_points() {
        // Interior point must be discarded; hull is the 4 corners.
        let pts = vec![
            (0.0, 0.0),
            (10.0, 0.0),
            (10.0, 10.0),
            (0.0, 10.0),
            (5.0, 5.0), // interior
        ];
        let hull = convex_hull(&pts);
        assert_eq!(hull.len(), 4, "interior point dropped: {hull:?}");
        for corner in [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)] {
            assert!(hull.contains(&corner), "missing {corner:?} in {hull:?}");
        }
    }

    // ---------- detail culling ----------

    fn cull_proj() -> Equirectangular {
        let bb = BBox {
            min_lon: 0.0,
            min_lat: 0.0,
            max_lon: 100.0,
            max_lat: 100.0,
        };
        Equirectangular::fit(bb, (100.0, 100.0))
    }

    fn cull_square(lon: f64, lat: f64, side: f64) -> crate::geometry::Polygon {
        crate::geometry::Polygon {
            outer: vec![
                LonLat { lon, lat },
                LonLat { lon: lon + side, lat },
                LonLat { lon: lon + side, lat: lat + side },
                LonLat { lon, lat: lat + side },
            ],
            holes: vec![],
        }
    }

    #[test]
    fn keep_hole_drops_subpixel_but_keeps_visible() {
        let p = cull_proj(); // 1 lon/lat unit == 1 px
        let detail = RenderDetail {
            min_island_px2: 9.0,
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        // 1×1 deg hole ≈ 1 px² — below the 9 px² floor → dropped.
        let tiny = cull_square(10.0, 10.0, 1.0).outer;
        assert!(!keep_hole(&p, &tiny, detail));
        // 5×5 deg hole = 25 px² — visible → kept.
        let big = cull_square(10.0, 10.0, 5.0).outer;
        assert!(keep_hole(&p, &big, detail));
        // Threshold of zero keeps everything.
        let off = RenderDetail { min_island_px2: 0.0, ..detail };
        assert!(keep_hole(&p, &tiny, off));
    }

    #[test]
    fn cull_drops_tiny_islands_beside_dominant_mass() {
        let p = cull_proj();
        let polys = vec![
            cull_square(0.0, 0.0, 40.0), // dominant landmass
            cull_square(60.0, 0.0, 1.0), // speck
            cull_square(70.0, 0.0, 1.0), // speck
        ];
        let detail = RenderDetail {
            min_island_px2: 9.0, // 3×3 px floor; specks are ~1 px²
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let keep = cull_components(&p, &polys, detail);
        assert_eq!(keep, vec![true, false, false], "specks beside a big mass drop");
    }

    #[test]
    fn cull_keeps_clusters_of_equal_islands() {
        let p = cull_proj();
        // Five equal small islands — none dominates, so the relative
        // escape hatch keeps them all even below the absolute floor.
        let polys: Vec<_> = (0..5).map(|i| cull_square(i as f64 * 5.0, 0.0, 1.0)).collect();
        let detail = RenderDetail {
            min_island_px2: 9.0,
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let keep = cull_components(&p, &polys, detail);
        assert_eq!(keep, vec![true; 5], "comparable islands all survive");
    }

    #[test]
    fn cull_keeps_individually_visible_island() {
        let p = cull_proj();
        let polys = vec![
            cull_square(0.0, 0.0, 40.0), // dominant
            cull_square(60.0, 0.0, 5.0), // 25 px² — visible
            cull_square(80.0, 0.0, 1.0), // 1 px² — speck
        ];
        let detail = RenderDetail {
            min_island_px2: 9.0,
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let keep = cull_components(&p, &polys, detail);
        assert_eq!(keep, vec![true, true, false], "visible island stays, speck drops");
    }

    #[test]
    fn cull_always_keeps_largest_even_if_sub_threshold() {
        let p = cull_proj();
        // A single tiny island that is itself the answer: zoomed far
        // out it's below the floor, but the largest is always kept.
        let polys = vec![cull_square(0.0, 0.0, 1.0)];
        let detail = RenderDetail {
            min_island_px2: 9.0,
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let keep = cull_components(&p, &polys, detail);
        assert_eq!(keep, vec![true], "lone tiny island never GC'd");
    }

    #[test]
    fn cull_disabled_when_floor_zero() {
        let p = cull_proj();
        let polys = vec![
            cull_square(0.0, 0.0, 40.0),
            cull_square(60.0, 0.0, 1.0),
        ];
        let detail = RenderDetail {
            min_island_px2: 0.0,
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let keep = cull_components(&p, &polys, detail);
        assert_eq!(keep, vec![true, true], "floor 0 disables culling");
    }

    #[test]
    fn cull_reduces_multipolygon_subpaths() {
        let p = cull_proj();
        let mut polys = vec![cull_square(0.0, 0.0, 40.0)];
        // 3 px specks: big enough to survive the degenerate-ring drop, so
        // this test isolates *area* culling rather than simplification.
        for i in 0..20 {
            polys.push(cull_square(50.0 + (i % 5) as f64 * 4.0, (i / 5) as f64 * 4.0, 3.0));
        }
        let g = Geometry::MultiPolygon(polys);
        let detail = RenderDetail {
            min_island_px2: 16.0, // 4 px floor; specks are 9 px²
            island_rel_frac: 0.05,
            simplify_px: 1.0,
        };
        let mut culled = String::new();
        write_feature(&mut culled, &p, &g, detail);
        let mut full = String::new();
        write_feature(&mut full, &p, &g, RenderDetail::default());
        assert!(
            culled.matches('M').count() < full.matches('M').count(),
            "culling drops subpaths: culled={} full={}",
            culled.matches('M').count(),
            full.matches('M').count()
        );
        // The dominant mass survives.
        assert!(culled.contains("<path"), "main landmass kept: {culled}");
    }
}
