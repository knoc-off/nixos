//! Custom named geometry: `geo/<name>` refs read `<geo_dir>/<name>.geojson`,
//! a project's own features (a wall, a trade route, a historic border)
//! that no bundled dataset carries. Files live in the cards repo, so they
//! are versioned and render offline. `define` builds them from OSM ids,
//! an Overpass query, or GeoJSON, simplified to a size budget.

use std::path::{Path, PathBuf};

use crate::data::{geoboundaries, overpass};
use crate::error::MapError;
use crate::geometry::{Geometry, LonLat, Polygon};

pub const PREFIX: &str = "geo/";
/// Budget for a saved feature; bigger inputs are simplified down to it.
const MAX_POINTS: usize = 20_000;

/// Validate a feature name: lowercase kebab, optional `/` folders.
pub fn check_name(name: &str) -> Result<(), MapError> {
    let ok = !name.is_empty()
        && name.split('/').all(|seg| {
            !seg.is_empty()
                && seg.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '_')
        });
    if ok {
        Ok(())
    } else {
        Err(MapError::Resolve(format!(
            "bad geo name `{name}`: use lowercase letters, digits, - and _, with / for folders"
        )))
    }
}

pub fn path(dir: &Path, name: &str) -> Result<PathBuf, MapError> {
    check_name(name)?;
    Ok(dir.join(format!("{name}.geojson")))
}

/// Read `geo/<name>`.
pub fn resolve(dir: Option<&Path>, name: &str) -> Result<Geometry, MapError> {
    let dir = dir.ok_or_else(|| MapError::Resolve("geo/ refs need a project (.marki/geo/)".into()))?;
    let p = path(dir, name)?;
    let raw = std::fs::read(&p).map_err(|_| {
        MapError::Resolve(format!(
            "unknown geo/{name}: no {}; create it with marki_map_define or list existing ones with marki_map_list",
            p.display()
        ))
    })?;
    let v: serde_json::Value =
        serde_json::from_slice(&raw).map_err(|e| MapError::Resolve(format!("geo/{name}: {e}")))?;
    from_geojson(&v).map_err(|e| MapError::Resolve(format!("geo/{name}: {e}")))
}

/// Bytes of every `geo/` file a set of refs uses, for the render cache
/// key: editing a feature file must re-render the maps using it.
pub fn fingerprint<'a>(dir: Option<&Path>, refs: impl Iterator<Item = &'a String>) -> Vec<u8> {
    let mut out = Vec::new();
    for r in refs {
        if let (Some(name), Some(dir)) = (r.strip_prefix(PREFIX), dir) {
            if let Ok(p) = path(dir, name) {
                out.extend(r.as_bytes());
                out.extend(std::fs::read(p).unwrap_or_default());
            }
        }
    }
    out
}

/// A GeoJSON Geometry, Feature or FeatureCollection -> one [`Geometry`].
pub fn from_geojson(v: &serde_json::Value) -> Result<Geometry, String> {
    let parts: Vec<Geometry> = match v.get("type").and_then(|t| t.as_str()) {
        Some("FeatureCollection") => v["features"]
            .as_array()
            .ok_or("FeatureCollection without features")?
            .iter()
            .map(from_geojson)
            .collect::<Result<_, _>>()?,
        Some("Feature") => vec![from_geojson(&v["geometry"])?],
        Some("GeometryCollection") => v["geometries"]
            .as_array()
            .ok_or("GeometryCollection without geometries")?
            .iter()
            .map(from_geojson)
            .collect::<Result<_, _>>()?,
        Some("MultiPoint") => return Err("MultiPoint is not supported; use separate features".into()),
        Some(_) => vec![geoboundaries::json_to_geometry(v).ok_or("malformed geometry")?],
        None => return Err("not GeoJSON (no \"type\")".into()),
    };
    merge(parts).ok_or_else(|| "no geometry".into())
}

/// Combine parts into one geometry: polygons into a MultiPolygon, lines
/// into a MultiLineString, a lone point stays a point. Mixed kinds give
/// `None`: one feature is one kind, so it styles consistently.
fn merge(parts: Vec<Geometry>) -> Option<Geometry> {
    let mut polys: Vec<Polygon> = Vec::new();
    let mut lines: Vec<Vec<LonLat>> = Vec::new();
    let mut points: Vec<LonLat> = Vec::new();
    for g in parts {
        match g {
            Geometry::Polygon { outer, holes } => polys.push(Polygon { outer, holes }),
            Geometry::MultiPolygon(ps) => polys.extend(ps),
            Geometry::LineString(l) => lines.push(l),
            Geometry::MultiLineString(ls) => lines.extend(ls),
            Geometry::Point(p) => points.push(p),
        }
    }
    match (polys.is_empty(), lines.is_empty(), points.len()) {
        (false, true, 0) if polys.len() == 1 => {
            let p = polys.pop()?;
            Some(Geometry::Polygon { outer: p.outer, holes: p.holes })
        }
        (false, true, 0) => Some(Geometry::MultiPolygon(polys)),
        (true, false, 0) if lines.len() == 1 => Some(Geometry::LineString(lines.pop()?)),
        (true, false, 0) => Some(Geometry::MultiLineString(lines)),
        (true, true, 1) => Some(Geometry::Point(points[0])),
        _ => None,
    }
}

/// [`Geometry`] -> GeoJSON geometry object, coordinates rounded to ~1 m.
pub fn to_geojson(g: &Geometry) -> serde_json::Value {
    let pt = |p: &LonLat| serde_json::json!([round(p.lon), round(p.lat)]);
    let line = |l: &[LonLat]| l.iter().map(pt).collect::<Vec<_>>();
    let poly = |outer: &[LonLat], holes: &[Vec<LonLat>]| {
        std::iter::once(line(outer)).chain(holes.iter().map(|h| line(h))).collect::<Vec<_>>()
    };
    match g {
        Geometry::Point(p) => serde_json::json!({"type": "Point", "coordinates": pt(p)}),
        Geometry::LineString(l) => serde_json::json!({"type": "LineString", "coordinates": line(l)}),
        Geometry::MultiLineString(ls) => serde_json::json!({
            "type": "MultiLineString", "coordinates": ls.iter().map(|l| line(l)).collect::<Vec<_>>()
        }),
        Geometry::Polygon { outer, holes } => serde_json::json!({"type": "Polygon", "coordinates": poly(outer, holes)}),
        Geometry::MultiPolygon(ps) => serde_json::json!({
            "type": "MultiPolygon", "coordinates": ps.iter().map(|p| poly(&p.outer, &p.holes)).collect::<Vec<_>>()
        }),
    }
}

fn round(x: f64) -> f64 {
    (x * 1e5).round() / 1e5
}

pub fn point_count(g: &Geometry) -> usize {
    match g {
        Geometry::Point(_) => 1,
        Geometry::LineString(l) => l.len(),
        Geometry::MultiLineString(ls) => ls.iter().map(Vec::len).sum(),
        Geometry::Polygon { outer, holes } => outer.len() + holes.iter().map(Vec::len).sum::<usize>(),
        Geometry::MultiPolygon(ps) => ps.iter().map(|p| p.outer.len() + p.holes.iter().map(Vec::len).sum::<usize>()).sum(),
    }
}

/// Douglas-Peucker in degrees, doubling the tolerance until the feature
/// fits [`MAX_POINTS`]. Returns the tolerance used (0 = untouched).
pub fn simplify_to_budget(g: &mut Geometry) -> f64 {
    let mut eps = 0.0;
    let original = g.clone();
    while point_count(g) > MAX_POINTS {
        eps = if eps == 0.0 { 1e-4 } else { eps * 2.0 };
        *g = original.clone();
        simplify_geometry(g, eps);
    }
    eps
}

fn simplify_geometry(g: &mut Geometry, eps: f64) {
    let s = |l: &mut Vec<LonLat>, min: usize| {
        let pts: Vec<(f64, f64)> = l.iter().map(|p| (p.lon, p.lat)).collect();
        let out = crate::simplify::simplify(&pts, eps);
        if out.len() >= min {
            *l = out.into_iter().map(|(lon, lat)| LonLat { lon, lat }).collect();
        }
    };
    match g {
        Geometry::Point(_) => {}
        Geometry::LineString(l) => s(l, 2),
        Geometry::MultiLineString(ls) => ls.iter_mut().for_each(|l| s(l, 2)),
        Geometry::Polygon { outer, holes } => {
            s(outer, 4);
            holes.iter_mut().for_each(|h| s(h, 4));
        }
        Geometry::MultiPolygon(ps) => ps.iter_mut().for_each(|p| {
            s(&mut p.outer, 4);
            p.holes.iter_mut().for_each(|h| s(h, 4));
        }),
    }
}

/// Where a custom feature comes from.
pub enum Source<'a> {
    /// `relation/N` / `way/N` refs, merged.
    Osm(Vec<String>),
    /// An Overpass QL statement selecting ways/relations, e.g.
    /// `way[historic=citywalls][name="Great Wall of China"](30,95,45,125);`
    Overpass(&'a str),
    /// GeoJSON geometry, Feature or FeatureCollection.
    GeoJson(&'a serde_json::Value),
}

/// Build, simplify and save `geo/<name>`. Returns a summary for the author.
pub fn define(dir: &Path, name: &str, source: Source<'_>, cache_root: &Path) -> Result<serde_json::Value, MapError> {
    let dest = path(dir, name)?;
    let mut g = match source {
        Source::Osm(refs) => {
            if refs.is_empty() || refs.len() > 200 {
                return Err(MapError::Resolve("osm: give 1 to 200 relation/N or way/N refs".into()));
            }
            let parts = refs
                .iter()
                .map(|r| {
                    if !(r.starts_with("relation/") || r.starts_with("way/")) {
                        return Err(MapError::Resolve(format!("osm refs are relation/N or way/N, got `{r}`")));
                    }
                    overpass::resolve(r, cache_root)
                })
                .collect::<Result<Vec<_>, _>>()?;
            merge(parts).ok_or_else(|| MapError::Resolve("osm refs mix areas and lines; define them separately".into()))?
        }
        Source::Overpass(q) => overpass::query(q, cache_root)?,
        Source::GeoJson(v) => from_geojson(v).map_err(|e| MapError::Resolve(format!("geojson: {e}")))?,
    };
    let before = point_count(&g);
    let eps = simplify_to_budget(&mut g);
    let bbox = g.bbox();
    let body = serde_json::json!({"type": "Feature", "properties": {"name": name}, "geometry": to_geojson(&g)});
    if let Some(d) = dest.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::write(&dest, serde_json::to_vec(&body).map_err(|e| MapError::Internal(e.to_string()))?)?;
    Ok(serde_json::json!({
        "ref": format!("{PREFIX}{name}"),
        "kind": kind(&g),
        "points": point_count(&g),
        "points_before_simplify": before,
        "simplify_degrees": eps,
        "bbox": [round(bbox.min_lon), round(bbox.min_lat), round(bbox.max_lon), round(bbox.max_lat)],
        "bytes": std::fs::metadata(&dest).map(|m| m.len()).unwrap_or(0),
    }))
}

fn kind(g: &Geometry) -> &'static str {
    match g {
        Geometry::Point(_) => "point",
        Geometry::LineString(_) | Geometry::MultiLineString(_) => "line",
        Geometry::Polygon { .. } | Geometry::MultiPolygon(_) => "area",
    }
}

/// Every `geo/<name>` under `dir`, sorted.
pub fn list(dir: &Path) -> Vec<String> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        let Ok(rd) = std::fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else if p.extension().is_some_and(|x| x == "geojson") {
                if let Ok(rel) = p.with_extension("").strip_prefix(dir) {
                    out.push(format!("{PREFIX}{}", rel.to_string_lossy().replace('\\', "/")));
                }
            }
        }
    }
    out.sort();
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp() -> PathBuf {
        let d = std::env::temp_dir().join(format!("marki-geo-{}-{:?}", std::process::id(), std::thread::current().id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn names_are_checked() {
        assert!(check_name("great-wall").is_ok() && check_name("china/great_wall2").is_ok());
        for bad in ["", "../x", "Great", "a//b", "a b"] {
            assert!(check_name(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn feature_collection_of_lines_merges() {
        let v = serde_json::json!({"type": "FeatureCollection", "features": [
            {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[100, 40], [101, 40.5]]}},
            {"type": "Feature", "geometry": {"type": "MultiLineString", "coordinates": [[[102, 41], [103, 41]]]}}
        ]});
        match from_geojson(&v).unwrap() {
            Geometry::MultiLineString(ls) => assert_eq!(ls.len(), 2),
            g => panic!("{g:?}"),
        }
        let mixed = serde_json::json!({"type": "GeometryCollection", "geometries": [
            {"type": "Point", "coordinates": [1, 2]},
            {"type": "LineString", "coordinates": [[1, 2], [3, 4]]}
        ]});
        assert!(from_geojson(&mixed).is_err());
    }

    #[test]
    fn define_simplifies_saves_and_round_trips() {
        let d = tmp();
        // A 50k-point wiggly line: must come out under budget.
        let coords: Vec<_> = (0..50_000)
            .map(|i| {
                let x = i as f64 / 1000.0;
                serde_json::json!([100.0 + x, 40.0 + (x * 7.0).sin() * 0.01])
            })
            .collect();
        let v = serde_json::json!({"type": "LineString", "coordinates": coords});
        let out = define(&d, "wall", Source::GeoJson(&v), &d).unwrap();
        assert_eq!(out["ref"], "geo/wall");
        assert_eq!(out["kind"], "line");
        assert!(out["points"].as_u64().unwrap() <= MAX_POINTS as u64, "{out}");
        let back = resolve(Some(&d), "wall").unwrap();
        assert_eq!(point_count(&back), out["points"].as_u64().unwrap() as usize);
        assert_eq!(list(&d), ["geo/wall"]);
        assert!(resolve(Some(&d), "nope").unwrap_err().to_string().contains("marki_map_define"));
        // The fingerprint follows file contents.
        let refs = vec!["geo/wall".to_string()];
        let a = fingerprint(Some(&d), refs.iter());
        std::fs::write(d.join("wall.geojson"), br#"{"type":"Point","coordinates":[1,2]}"#).unwrap();
        assert_ne!(a, fingerprint(Some(&d), refs.iter()));
        let _ = std::fs::remove_dir_all(&d);
    }
}
