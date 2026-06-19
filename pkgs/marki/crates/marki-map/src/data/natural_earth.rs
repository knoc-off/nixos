//! Natural Earth coastline loader.
//!
//! geoBoundaries carries no coastline layer, so we keep Natural Earth
//! solely for `coastline` references. `NATURAL_EARTH_DATA` (set by the
//! markid module) points at a directory containing the
//! `ne_10m_coastline` shapefile set (`.shp` + `.shx` + `.dbf`).
//!
//! `coastline` is parameter-free: it returns every coastline polyline
//! flattened into one MultiLineString. The projection's bbox crops it
//! to whatever else has been drawn.

use crate::data::geo_common::normalize_antimeridian;
use crate::error::MapError;
use crate::geometry::{Geometry, LonLat};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

/// Path to the Natural Earth data directory. Reads `NATURAL_EARTH_DATA`
/// at first call; cached for the process lifetime.
fn data_dir() -> Result<PathBuf, MapError> {
    static DIR: OnceLock<Result<PathBuf, String>> = OnceLock::new();
    let r = DIR.get_or_init(|| match std::env::var("NATURAL_EARTH_DATA") {
        Ok(s) if !s.is_empty() => Ok(PathBuf::from(s)),
        _ => Err("NATURAL_EARTH_DATA env not set".to_string()),
    });
    match r {
        Ok(p) => Ok(p.clone()),
        Err(e) => Err(MapError::Resolve(e.clone())),
    }
}

/// Process-global lazily-loaded coastline geometry (one MultiLineString).
fn coastline() -> Result<&'static Geometry, MapError> {
    static GEOM: OnceLock<Result<Geometry, String>> = OnceLock::new();
    static LOAD_LOCK: Mutex<()> = Mutex::new(());

    if let Some(r) = GEOM.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let _guard = LOAD_LOCK.lock().unwrap();
    if let Some(r) = GEOM.get() {
        return r.as_ref().map_err(|e| MapError::Resolve(e.clone()));
    }
    let dir = match data_dir() {
        Ok(d) => d,
        Err(e) => {
            let _ = GEOM.set(Err(e.to_string()));
            return Err(e);
        }
    };
    let built = load_coastline(&dir).map_err(|e| e.to_string());
    let _ = GEOM.set(built);
    GEOM.get()
        .unwrap()
        .as_ref()
        .map_err(|e| MapError::Resolve(e.clone()))
}

/// Resolve the `coastline` reference. No other refs are handled here.
pub fn resolve_feature(name: &str) -> Result<Geometry, MapError> {
    if name == "coastline" {
        return coastline().cloned();
    }
    Err(MapError::Resolve(format!("unsupported feature ref: {name}")))
}

fn load_coastline(dir: &Path) -> Result<Geometry, MapError> {
    let path = dir.join("ne_10m_coastline.shp");
    if !path.exists() {
        tracing::warn!(
            "natural-earth: missing {}; coastline refs will fail",
            path.display()
        );
        return Ok(Geometry::MultiLineString(Vec::new()));
    }
    let mut reader = shapefile::Reader::from_path(&path)
        .map_err(|e| MapError::Resolve(format!("read {}: {e}", path.display())))?;
    let mut lines: Vec<Vec<LonLat>> = Vec::new();
    for rec in reader.iter_shapes_and_records() {
        let (shape, _) = rec.map_err(|e| MapError::Resolve(format!("ne_coastline row: {e}")))?;
        if let shapefile::Shape::Polyline(line) = shape {
            for part in line.into_inner() {
                let mut pts: Vec<LonLat> = part
                    .into_iter()
                    .map(|p| LonLat { lon: p.x, lat: p.y })
                    .collect();
                normalize_antimeridian(&mut pts);
                lines.push(pts);
            }
        }
    }
    Ok(Geometry::MultiLineString(lines))
}
