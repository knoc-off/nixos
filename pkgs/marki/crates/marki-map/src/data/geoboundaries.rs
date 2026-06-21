//! geoBoundaries gbOpen loader.
//!
//! `GEOBOUNDARIES_DATA` env (set by the markid module) points at a
//! directory produced by the `geoboundaries-data` derivation: one
//! `<ISO3>_ADM<n>.geojson` (simplified geometry) per country/level plus
//! a `meta.csv` carrying the ISO3 → Continent / UN-subregion mapping.
//!
//! Lookups are by:
//!
//!   * `country/<ISO3>` — one country polygon (or multipolygon) by
//!     three-letter ISO code (`DEU`, `FRA`, …). Source: gbOpen ADM0.
//!   * `adm1/<ISO3>/<NAME>`, `adm2/<ISO3>/<NAME>`, `adm3/<ISO3>/<NAME>`
//!     — one administrative entry at the given geoBoundaries level,
//!     keyed by the local `shapeName` (case-insensitive). Note: which
//!     real-world division a level maps to varies by country (e.g.
//!     Italy ADM1 = statistical macroregions, ADM2 = regioni, ADM3 =
//!     province), so authors choose the level that matches the country.
//!   * `neighbors/<ISO3>` — every country sharing a border segment with
//!     the target (topological adjacency). Falls back to bbox-intersect
//!     for island nations with no shared edges.
//!   * `continent/<NAME>` and `subregion/<NAME>` — composite of every
//!     country whose meta-CSV `Continent` / `UNSDG-subregion` matches.
//!
//! The resolver caches the parsed dataset per process; subsequent
//! lookups are in-memory.

use crate::data::geo_common::{
    build_neighbor_graph, fold_into_composites, normalize_antimeridian,
    stitch_dateline_polygons, Feature,
};
use crate::error::MapError;
use crate::geometry::{BBox, Geometry, LonLat, Polygon};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

/// Administrative levels bundled by the data derivation and exposed via
/// `adm<N>/` references.
const ADM_LEVELS: [u8; 3] = [1, 2, 3];

#[derive(Default)]
struct GbIndex {
    /// Country polygon by ISO3 (gbOpen ADM0).
    countries: HashMap<String, Feature>,
    /// Admin entries by (level, ISO3, lower_case shapeName).
    admin: HashMap<(u8, String, String), Feature>,
    /// Continent composites by lowercase continent name.
    continents: HashMap<String, Feature>,
    /// UN subregion composites by lowercase subregion name.
    subregions: HashMap<String, Feature>,
    /// ISO3 → bbox, used by the bbox-intersect neighbour fallback.
    country_bbox: HashMap<String, BBox>,
    /// ISO3 → sorted border-sharing ISO3s.
    neighbors: HashMap<String, Vec<String>>,
}

/// Path to the geoBoundaries data directory. Reads `GEOBOUNDARIES_DATA`
/// at first call; cached for the process lifetime.
fn data_dir() -> Result<PathBuf, MapError> {
    static DIR: OnceLock<Result<PathBuf, String>> = OnceLock::new();
    let r = DIR.get_or_init(|| match std::env::var("GEOBOUNDARIES_DATA") {
        Ok(s) if !s.is_empty() => Ok(PathBuf::from(s)),
        _ => Err("GEOBOUNDARIES_DATA env not set".to_string()),
    });
    match r {
        Ok(p) => Ok(p.clone()),
        Err(e) => Err(MapError::Resolve(e.clone())),
    }
}

/// Process-global lazily-loaded geoBoundaries index.
fn index() -> Result<&'static GbIndex, MapError> {
    static INDEX: OnceLock<Result<GbIndex, String>> = OnceLock::new();
    static LOAD_LOCK: Mutex<()> = Mutex::new(());

    if let Some(r) = INDEX.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let _guard = LOAD_LOCK.lock().unwrap();
    if let Some(r) = INDEX.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let dir = match data_dir() {
        Ok(d) => d,
        Err(e) => {
            let _ = INDEX.set(Err(e.to_string()));
            return Err(e);
        }
    };
    let built = build_index(&dir).map_err(|e| e.to_string());
    let _ = INDEX.set(built);
    INDEX
        .get()
        .unwrap()
        .as_ref()
        .map_err(|e| MapError::Resolve(e.clone()))
}

/// Resolve one feature reference like `country/DEU` or `adm1/DEU/Bayern`
/// to a [`Geometry`]. `neighbors`, `continent` and `subregion` return
/// composites.
pub fn resolve_feature(name: &str) -> Result<Geometry, MapError> {
    let idx = index()?;
    if let Some(rest) = name.strip_prefix("country/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "country refs take no modifier; got `{name}`"
            )));
        }
        let feat = idx
            .countries
            .get(rest)
            .ok_or_else(|| MapError::Resolve(format!("unknown country: {rest}")))?;
        return Ok(feat.geom.clone());
    }
    for lvl in ADM_LEVELS {
        let prefix = format!("adm{lvl}/");
        if let Some(rest) = name.strip_prefix(&prefix) {
            let (iso, unit) = rest
                .split_once('/')
                .ok_or_else(|| MapError::Resolve(format!("bad adm{lvl} ref: {name}")))?;
            let key = (lvl, iso.to_string(), unit.to_lowercase());
            return idx
                .admin
                .get(&key)
                .map(|f| f.geom.clone())
                .ok_or_else(|| MapError::Resolve(format!("unknown adm{lvl}: {iso}/{unit}")));
        }
    }
    if let Some(rest) = name.strip_prefix("neighbors/") {
        idx.countries
            .get(rest)
            .ok_or_else(|| MapError::Resolve(format!("unknown country for neighbors: {rest}")))?;
        let isos: Vec<&str> = match idx.neighbors.get(rest) {
            Some(v) if !v.is_empty() => v.iter().map(|s| s.as_str()).collect(),
            _ => fallback_bbox_neighbors(rest, idx),
        };
        let mut polys: Vec<Polygon> = Vec::new();
        for iso in isos {
            if let Some(feat) = idx.countries.get(iso) {
                match &feat.geom {
                    Geometry::Polygon { outer, holes } => polys.push(Polygon {
                        outer: outer.clone(),
                        holes: holes.clone(),
                    }),
                    Geometry::MultiPolygon(ps) => polys.extend(ps.iter().cloned()),
                    _ => {}
                }
            }
        }
        return Ok(Geometry::MultiPolygon(polys));
    }
    if let Some(rest) = name.strip_prefix("continent/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "continent refs take no modifier; got `{name}`"
            )));
        }
        return idx
            .continents
            .get(&rest.to_lowercase())
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown continent: {rest}")));
    }
    if let Some(rest) = name.strip_prefix("subregion/") {
        if rest.contains('/') {
            return Err(MapError::Resolve(format!(
                "subregion refs take no modifier; got `{name}`"
            )));
        }
        return idx
            .subregions
            .get(&rest.to_lowercase())
            .map(|f| f.geom.clone())
            .ok_or_else(|| MapError::Resolve(format!("unknown subregion: {rest}")));
    }
    Err(MapError::Resolve(format!("unsupported feature ref: {name}")))
}

/// Fallback: ISOs whose bbox intersects the target's bbox. Used when the
/// topological graph has no entries for the target (island nations).
fn fallback_bbox_neighbors<'a>(iso: &str, idx: &'a GbIndex) -> Vec<&'a str> {
    let target = match idx.country_bbox.get(iso) {
        Some(b) => b,
        None => return vec![],
    };
    idx.countries
        .iter()
        .filter(|(k, feat)| k.as_str() != iso && feat.bbox.intersects(target))
        .map(|(k, _)| k.as_str())
        .collect()
}

// ---------- index construction ----------

fn build_index(dir: &Path) -> Result<GbIndex, MapError> {
    let mut idx = GbIndex::default();

    // Countries (ADM0).
    let mut loaded_any = false;
    for entry in read_geojson_dir(dir)? {
        let (iso, lvl) = match parse_filename(&entry) {
            Some(v) => v,
            None => continue,
        };
        let features = load_geojson(&entry)?;
        loaded_any = true;
        if lvl == 0 {
            for (name, geom) in features {
                let _ = name; // ADM0 shapeName is the country name; we key by ISO.
                let feat = Feature::new(geom);
                idx.country_bbox.insert(iso.clone(), feat.bbox);
                idx.countries.insert(iso.clone(), feat);
            }
        } else if ADM_LEVELS.contains(&lvl) {
            for (name, geom) in features {
                let feat = Feature::new(geom);
                let key = (lvl, iso.clone(), name.to_lowercase());
                idx.admin.entry(key).or_insert(feat);
            }
        }
    }

    if !loaded_any {
        tracing::warn!(
            "geoboundaries: no *.geojson found under {}; country/adm* refs will fail",
            dir.display()
        );
    }

    // Continent / subregion composites from the metadata CSV.
    build_groups(dir, &mut idx);

    // Topological neighbour graph from country polygons.
    idx.neighbors =
        build_neighbor_graph(idx.countries.iter().map(|(iso, f)| (iso, &f.geom)));

    Ok(idx)
}

/// List `*.geojson` files in the data dir.
fn read_geojson_dir(dir: &Path) -> Result<Vec<PathBuf>, MapError> {
    let rd = std::fs::read_dir(dir)
        .map_err(|e| MapError::Resolve(format!("read dir {}: {e}", dir.display())))?;
    let mut out = Vec::new();
    for ent in rd {
        let ent = ent.map_err(|e| MapError::Resolve(format!("dir entry: {e}")))?;
        let p = ent.path();
        if p.extension().map(|e| e == "geojson").unwrap_or(false) {
            out.push(p);
        }
    }
    out.sort();
    Ok(out)
}

/// `DEU_ADM1.geojson` → (`DEU`, 1). Returns `None` for anything that
/// doesn't match the expected naming.
fn parse_filename(path: &Path) -> Option<(String, u8)> {
    let stem = path.file_stem()?.to_str()?;
    let (iso, adm) = stem.split_once('_')?;
    let lvl: u8 = adm.strip_prefix("ADM")?.parse().ok()?;
    if iso.len() != 3 || !iso.chars().all(|c| c.is_ascii_uppercase()) {
        return None;
    }
    Some((iso.to_string(), lvl))
}

/// Parse a gbOpen GeoJSON FeatureCollection into `(shapeName, Geometry)`
/// pairs. Only Polygon / MultiPolygon geometries are kept.
fn load_geojson(path: &Path) -> Result<Vec<(String, Geometry)>, MapError> {
    let bytes = std::fs::read(path)
        .map_err(|e| MapError::Resolve(format!("read {}: {e}", path.display())))?;
    let v: serde_json::Value = serde_json::from_slice(&bytes)
        .map_err(|e| MapError::Resolve(format!("parse {}: {e}", path.display())))?;
    let features = v
        .get("features")
        .and_then(|f| f.as_array())
        .ok_or_else(|| MapError::Resolve(format!("{}: no features array", path.display())))?;

    let mut out = Vec::with_capacity(features.len());
    for feat in features {
        let name = feat
            .get("properties")
            .and_then(|p| p.get("shapeName"))
            .and_then(|n| n.as_str())
            .unwrap_or("")
            .trim()
            .to_string();
        let geom = match feat.get("geometry") {
            Some(g) => g,
            None => continue,
        };
        if let Some(g) = json_to_geometry(geom) {
            out.push((name, g));
        }
    }
    Ok(out)
}

/// Convert a GeoJSON geometry object into our internal [`Geometry`].
fn json_to_geometry(g: &serde_json::Value) -> Option<Geometry> {
    let ty = g.get("type")?.as_str()?;
    let coords = g.get("coordinates")?;
    match ty {
        "Polygon" => {
            let rings = parse_polygon_rings(coords)?;
            Some(rings_to_geometry(rings))
        }
        "MultiPolygon" => {
            let mut polys: Vec<Polygon> = Vec::new();
            for poly in coords.as_array()? {
                if let Some(rings) = parse_polygon_rings(poly) {
                    if let Some(p) = rings_to_polygon(rings) {
                        polys.push(p);
                    }
                }
            }
            let polys = stitch_dateline_polygons(polys);
            if polys.len() == 1 {
                let p = polys.into_iter().next().unwrap();
                Some(Geometry::Polygon { outer: p.outer, holes: p.holes })
            } else {
                Some(Geometry::MultiPolygon(polys))
            }
        }
        _ => None,
    }
}

/// Parse a GeoJSON polygon (array of rings, each an array of [lon,lat])
/// into rings of `LonLat`, applying antimeridian normalization per ring.
fn parse_polygon_rings(coords: &serde_json::Value) -> Option<Vec<Vec<LonLat>>> {
    let mut rings = Vec::new();
    for ring in coords.as_array()? {
        let mut pts: Vec<LonLat> = Vec::new();
        for pt in ring.as_array()? {
            let arr = pt.as_array()?;
            let lon = arr.first()?.as_f64()?;
            let lat = arr.get(1)?.as_f64()?;
            pts.push(LonLat { lon, lat });
        }
        normalize_antimeridian(&mut pts);
        rings.push(pts);
    }
    Some(rings)
}

/// First ring = outer, remaining = holes.
fn rings_to_polygon(mut rings: Vec<Vec<LonLat>>) -> Option<Polygon> {
    if rings.is_empty() {
        return None;
    }
    let outer = rings.remove(0);
    Some(Polygon { outer, holes: rings })
}

fn rings_to_geometry(rings: Vec<Vec<LonLat>>) -> Geometry {
    match rings_to_polygon(rings) {
        Some(p) => Geometry::Polygon { outer: p.outer, holes: p.holes },
        None => Geometry::MultiPolygon(Vec::new()),
    }
}

// ---------- continent / subregion grouping ----------

/// Read `meta.csv` and fold every country into its `Continent` and
/// `UNSDG-subregion` composite. Missing CSV is non-fatal (those refs
/// just won't resolve).
fn build_groups(dir: &Path, idx: &mut GbIndex) {
    let path = dir.join("meta.csv");
    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(_) => {
            tracing::warn!(
                "geoboundaries: missing {}; continent/subregion refs will fail",
                path.display()
            );
            return;
        }
    };
    let mut lines = text.lines();
    let header = match lines.next() {
        Some(h) => parse_csv_row(h),
        None => return,
    };
    let col = |name: &str| header.iter().position(|h| h == name);
    let (iso_c, type_c, cont_c, sub_c) = match (
        col("boundaryISO"),
        col("boundaryType"),
        col("Continent"),
        col("UNSDG-subregion"),
    ) {
        (Some(a), Some(b), Some(c), Some(d)) => (a, b, c, d),
        _ => {
            tracing::warn!("geoboundaries: meta.csv missing expected columns");
            return;
        }
    };

    // ISO3 → (continent, subregion), taken from the ADM0 row.
    let mut groups: HashMap<String, (Option<String>, Option<String>)> = HashMap::new();
    for line in lines {
        let row = parse_csv_row(line);
        let get = |i: usize| row.get(i).map(|s| s.trim().to_string());
        if get(type_c).as_deref() != Some("ADM0") {
            continue;
        }
        let iso = match get(iso_c) {
            Some(s) if !s.is_empty() => s,
            _ => continue,
        };
        let cont = get(cont_c).filter(|s| !s.is_empty());
        let sub = get(sub_c).filter(|s| !s.is_empty());
        groups.insert(iso, (cont, sub));
    }

    let mut continent_buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
    let mut subregion_buckets: HashMap<String, Vec<(Geometry, BBox)>> = HashMap::new();
    for (iso, feat) in &idx.countries {
        if let Some((cont, sub)) = groups.get(iso) {
            if let Some(c) = cont {
                continent_buckets
                    .entry(c.to_lowercase())
                    .or_default()
                    .push((feat.geom.clone(), feat.bbox));
            }
            if let Some(s) = sub {
                subregion_buckets
                    .entry(s.to_lowercase())
                    .or_default()
                    .push((feat.geom.clone(), feat.bbox));
            }
        }
    }
    fold_into_composites(continent_buckets, &mut idx.continents);
    fold_into_composites(subregion_buckets, &mut idx.subregions);
}

/// Minimal RFC-4180-ish CSV row tokenizer: handles double-quoted fields
/// with `""` escapes and embedded commas. geoBoundaries' meta CSV quotes
/// every field.
fn parse_csv_row(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut cur = String::new();
    let mut in_quotes = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' if in_quotes => {
                if chars.peek() == Some(&'"') {
                    cur.push('"');
                    chars.next();
                } else {
                    in_quotes = false;
                }
            }
            '"' => in_quotes = true,
            ',' if !in_quotes => {
                fields.push(std::mem::take(&mut cur));
            }
            _ => cur.push(c),
        }
    }
    fields.push(cur);
    fields
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_filename() {
        assert_eq!(
            parse_filename(Path::new("/x/DEU_ADM1.geojson")),
            Some(("DEU".to_string(), 1))
        );
        assert_eq!(
            parse_filename(Path::new("/x/USA_ADM0.geojson")),
            Some(("USA".to_string(), 0))
        );
        assert_eq!(parse_filename(Path::new("/x/meta.csv")), None);
        assert_eq!(parse_filename(Path::new("/x/lower_ADM1.geojson")), None);
    }

    #[test]
    fn json_polygon_to_geometry() {
        let g = serde_json::json!({
            "type": "Polygon",
            "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]]
        });
        match json_to_geometry(&g).unwrap() {
            Geometry::Polygon { outer, holes } => {
                assert_eq!(outer.len(), 5);
                assert!(holes.is_empty());
            }
            other => panic!("expected Polygon, got {other:?}"),
        }
    }

    #[test]
    fn json_polygon_with_hole() {
        let g = serde_json::json!({
            "type": "Polygon",
            "coordinates": [
                [[0.0, 0.0], [4.0, 0.0], [4.0, 4.0], [0.0, 4.0], [0.0, 0.0]],
                [[1.0, 1.0], [2.0, 1.0], [2.0, 2.0], [1.0, 2.0], [1.0, 1.0]]
            ]
        });
        match json_to_geometry(&g).unwrap() {
            Geometry::Polygon { holes, .. } => assert_eq!(holes.len(), 1),
            other => panic!("expected Polygon, got {other:?}"),
        }
    }

    #[test]
    fn json_multipolygon_to_geometry() {
        let g = serde_json::json!({
            "type": "MultiPolygon",
            "coordinates": [
                [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]],
                [[[5.0, 5.0], [6.0, 5.0], [6.0, 6.0], [5.0, 5.0]]]
            ]
        });
        match json_to_geometry(&g).unwrap() {
            Geometry::MultiPolygon(ps) => assert_eq!(ps.len(), 2),
            other => panic!("expected MultiPolygon, got {other:?}"),
        }
    }

    #[test]
    fn csv_row_handles_quotes_and_commas() {
        let row = parse_csv_row(r#""DEU","ADM0","Germany, Federal Republic","a""b""#);
        assert_eq!(row[0], "DEU");
        assert_eq!(row[1], "ADM0");
        assert_eq!(row[2], "Germany, Federal Republic");
        assert_eq!(row[3], "a\"b");
    }

    #[test]
    fn loads_feature_collection_from_str() {
        let fc = serde_json::json!({
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {"shapeName": "Bayern", "shapeGroup": "DEU"},
                    "geometry": {
                        "type": "Polygon",
                        "coordinates": [[[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]]
                    }
                }
            ]
        });
        // exercise the same extraction load_geojson performs
        let features = fc["features"].as_array().unwrap();
        let name = features[0]["properties"]["shapeName"].as_str().unwrap();
        assert_eq!(name, "Bayern");
        assert!(json_to_geometry(&features[0]["geometry"]).is_some());
    }
}
