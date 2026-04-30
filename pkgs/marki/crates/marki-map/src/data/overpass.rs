//! Overpass API client.
//!
//! For OSM `relation/N` and `way/M` references, we issue a single
//! [Overpass](https://overpass-api.de/) query and decode the returned
//! geometry. Responses are cached content-addressably under
//! `$XDG_CACHE_HOME/marki/net/overpass/`; cached entries don't expire
//! by default (per the RFC: "OSM features don't expire by default").
//!
//! Politeness:
//!   * 30s timeout
//!   * `User-Agent: marki/<version>`
//!   * 1 req/sec rate limit (process-global)
//!   * Exponential backoff on 429/504/timeouts (up to ~30s)
//!
//! Failures are converted to [`MapError::Network`] / `Resolve`. The
//! daemon turns each into a card-level failure and continues.

use crate::error::MapError;
use crate::geometry::{Geometry, LonLat, Polygon};
use serde::Deserialize;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const USER_AGENT: &str = concat!(
    "marki/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/knoc-off/nixos)"
);

const ENDPOINT: &str = "https://overpass-api.de/api/interpreter";
const HTTP_TIMEOUT: Duration = Duration::from_secs(30);
const MIN_INTERVAL: Duration = Duration::from_millis(1100);

/// Process-global last-request timestamp, for rate limiting.
static LAST_REQUEST: Mutex<Option<Instant>> = Mutex::new(None);

/// Resolve `relation/<N>` or `way/<M>` to a [`Geometry`]. The
/// `cache_root` is the daemon's cache dir; this function appends
/// `net/overpass/` itself.
pub fn resolve(reference: &str, cache_root: &Path) -> Result<Geometry, MapError> {
    let ql = build_query(reference)?;
    let cache_dir = cache_root.join("net").join("overpass");
    std::fs::create_dir_all(&cache_dir)?;
    let cache_file = cache_dir.join(format!("{}.json", query_key(&ql)));

    let raw = if cache_file.exists() {
        std::fs::read(&cache_file)?
    } else {
        let bytes = http_post(&ql)?;
        // Atomic write: tempfile + rename so a crash mid-write doesn't
        // leave a half-file in the cache.
        let tmp = cache_file.with_extension("tmp");
        std::fs::write(&tmp, &bytes)?;
        std::fs::rename(&tmp, &cache_file)?;
        bytes
    };

    decode_response(&raw, reference)
}

/// Stable cache filename: blake3-prefix-16 of the query string.
fn query_key(ql: &str) -> String {
    let h = blake3::hash(ql.as_bytes());
    h.to_hex().as_str()[..16].to_string()
}

/// Build an Overpass QL query that returns the referenced object's
/// geometry. We always request `out geom` so we get coordinates inline.
fn build_query(reference: &str) -> Result<String, MapError> {
    if let Some(rest) = reference.strip_prefix("relation/") {
        let n: i64 = rest
            .parse()
            .map_err(|_| MapError::Resolve(format!("bad relation id: {rest}")))?;
        // `[out:json][timeout:25]; relation(<n>); out geom;` — returns
        // the relation plus every member's geometry inline.
        return Ok(format!("[out:json][timeout:25];relation({n});out geom;"));
    }
    if let Some(rest) = reference.strip_prefix("way/") {
        let n: i64 = rest
            .parse()
            .map_err(|_| MapError::Resolve(format!("bad way id: {rest}")))?;
        return Ok(format!("[out:json][timeout:25];way({n});out geom;"));
    }
    Err(MapError::Resolve(format!(
        "overpass: unsupported ref `{reference}`"
    )))
}

/// POST a query to Overpass with backoff on 429/504. Returns the raw
/// JSON bytes on success.
fn http_post(ql: &str) -> Result<Vec<u8>, MapError> {
    let client = reqwest::blocking::Client::builder()
        .timeout(HTTP_TIMEOUT)
        .user_agent(USER_AGENT)
        .build()
        .map_err(|e| MapError::Network(format!("client: {e}")))?;

    let mut backoff = Duration::from_millis(500);
    let max_backoff = Duration::from_secs(30);
    let max_attempts = 5;

    for attempt in 0..max_attempts {
        rate_limit();
        match client.post(ENDPOINT).body(ql.to_string()).send() {
            Ok(resp) => {
                let status = resp.status();
                if status.is_success() {
                    return resp
                        .bytes()
                        .map(|b| b.to_vec())
                        .map_err(|e| MapError::Network(format!("read: {e}")));
                }
                // 429 Too Many Requests, 504 Gateway Timeout — back off.
                if status.as_u16() == 429 || status.as_u16() == 504 {
                    tracing::warn!(
                        "overpass {} attempt {}/{} — backing off {:?}",
                        status, attempt + 1, max_attempts, backoff
                    );
                    std::thread::sleep(backoff);
                    backoff = (backoff * 2).min(max_backoff);
                    continue;
                }
                return Err(MapError::Network(format!(
                    "overpass HTTP {status}"
                )));
            }
            Err(e) if attempt + 1 < max_attempts => {
                tracing::warn!(
                    "overpass error attempt {}/{}: {e}; backing off {:?}",
                    attempt + 1, max_attempts, backoff
                );
                std::thread::sleep(backoff);
                backoff = (backoff * 2).min(max_backoff);
            }
            Err(e) => return Err(MapError::Network(format!("send: {e}"))),
        }
    }
    Err(MapError::Network("overpass: gave up after retries".into()))
}

/// Block until at least `MIN_INTERVAL` has elapsed since the last
/// request from this process.
fn rate_limit() {
    let mut guard = LAST_REQUEST.lock().unwrap();
    if let Some(t) = *guard {
        let elapsed = t.elapsed();
        if elapsed < MIN_INTERVAL {
            std::thread::sleep(MIN_INTERVAL - elapsed);
        }
    }
    *guard = Some(Instant::now());
}

// ---------- response decoding ----------

#[derive(Deserialize)]
struct OverpassResponse {
    #[serde(default)]
    elements: Vec<OverpassElement>,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
enum OverpassElement {
    Way {
        #[serde(default)]
        geometry: Vec<NodeRef>,
    },
    Relation {
        #[serde(default)]
        members: Vec<RelationMember>,
    },
    Node(#[allow(dead_code)] serde_json::Value),
}

#[derive(Deserialize, Clone, Copy)]
struct NodeRef {
    lat: f64,
    lon: f64,
}

#[derive(Deserialize)]
struct RelationMember {
    #[serde(rename = "type")]
    member_type: String,
    #[serde(default)]
    role: String,
    #[serde(default)]
    geometry: Vec<NodeRef>,
}

fn decode_response(raw: &[u8], reference: &str) -> Result<Geometry, MapError> {
    let parsed: OverpassResponse = serde_json::from_slice(raw)
        .map_err(|e| MapError::Resolve(format!("overpass json: {e}")))?;

    if reference.starts_with("relation/") {
        return decode_relation(&parsed, reference);
    }
    if reference.starts_with("way/") {
        return decode_way(&parsed, reference);
    }
    Err(MapError::Resolve(format!(
        "overpass: unexpected ref shape `{reference}`"
    )))
}

fn decode_way(resp: &OverpassResponse, reference: &str) -> Result<Geometry, MapError> {
    for el in &resp.elements {
        if let OverpassElement::Way { geometry } = el {
            if geometry.is_empty() {
                continue;
            }
            let pts: Vec<LonLat> = geometry
                .iter()
                .map(|n| LonLat {
                    lon: n.lon,
                    lat: n.lat,
                })
                .collect();
            // If first==last we have a closed way (polygon); otherwise
            // a line.
            if pts.first() == pts.last() && pts.len() >= 4 {
                return Ok(Geometry::Polygon {
                    outer: pts,
                    holes: Vec::new(),
                });
            }
            return Ok(Geometry::LineString(pts));
        }
    }
    Err(MapError::Resolve(format!(
        "overpass: no way geometry for {reference}"
    )))
}

fn decode_relation(resp: &OverpassResponse, reference: &str) -> Result<Geometry, MapError> {
    for el in &resp.elements {
        if let OverpassElement::Relation { members } = el {
            // For multipolygon-style relations, each way member has a
            // `role` of "outer" or "inner". Stitch outer/inner pairs
            // into polygons. We assemble each ring greedily — pieces
            // are joined where their endpoints match.
            let outers = stitch_rings(members, "outer");
            let inners = stitch_rings(members, "inner");
            if outers.is_empty() {
                // Some relations are line-only. Fall through to that
                // case below.
                let lines: Vec<Vec<LonLat>> = members
                    .iter()
                    .filter(|m| m.member_type == "way" && !m.geometry.is_empty())
                    .map(|m| {
                        m.geometry
                            .iter()
                            .map(|n| LonLat {
                                lon: n.lon,
                                lat: n.lat,
                            })
                            .collect()
                    })
                    .collect();
                if !lines.is_empty() {
                    return Ok(Geometry::MultiLineString(lines));
                }
                continue;
            }
            // Match each inner to the smallest enclosing outer by
            // bbox containment — naive but correct for typical
            // admin-boundary relations.
            let mut polys: Vec<Polygon> = outers
                .iter()
                .map(|o| Polygon {
                    outer: o.clone(),
                    holes: Vec::new(),
                })
                .collect();
            for inner in &inners {
                if let Some(idx) = best_outer_for(inner, &polys) {
                    polys[idx].holes.push(inner.clone());
                }
            }
            if polys.len() == 1 {
                let p = polys.into_iter().next().unwrap();
                return Ok(Geometry::Polygon {
                    outer: p.outer,
                    holes: p.holes,
                });
            }
            return Ok(Geometry::MultiPolygon(polys));
        }
    }
    Err(MapError::Resolve(format!(
        "overpass: no relation geometry for {reference}"
    )))
}

fn stitch_rings(members: &[RelationMember], role: &str) -> Vec<Vec<LonLat>> {
    let parts: Vec<Vec<LonLat>> = members
        .iter()
        .filter(|m| m.member_type == "way" && m.role == role && !m.geometry.is_empty())
        .map(|m| {
            m.geometry
                .iter()
                .map(|n| LonLat {
                    lon: n.lon,
                    lat: n.lat,
                })
                .collect()
        })
        .collect();
    let mut remaining: Vec<Vec<LonLat>> = parts;
    let mut rings: Vec<Vec<LonLat>> = Vec::new();
    while let Some(mut current) = remaining.pop() {
        // If the segment is already closed, take it as-is.
        if current.first() == current.last() && current.len() >= 4 {
            rings.push(current);
            continue;
        }
        // Greedy join: find a remaining segment whose endpoint matches
        // ours, attach, repeat until closed or no progress.
        loop {
            let last = match current.last().copied() {
                Some(p) => p,
                None => break,
            };
            let mut matched = None;
            for (i, seg) in remaining.iter().enumerate() {
                if let (Some(start), Some(end)) = (seg.first(), seg.last()) {
                    if pt_eq(*start, last) {
                        matched = Some((i, false));
                        break;
                    }
                    if pt_eq(*end, last) {
                        matched = Some((i, true));
                        break;
                    }
                }
            }
            match matched {
                Some((i, reversed)) => {
                    let mut next = remaining.remove(i);
                    if reversed {
                        next.reverse();
                    }
                    // Skip the duplicate junction point.
                    if !next.is_empty() && current.last() == next.first() {
                        next.remove(0);
                    }
                    current.extend(next);
                    if current.first() == current.last() && current.len() >= 4 {
                        rings.push(current);
                        break;
                    }
                }
                None => {
                    // Couldn't close — keep as-is. Bad data but we'd
                    // rather render a partial outline than fail loudly.
                    rings.push(current);
                    break;
                }
            }
        }
    }
    rings
}

fn pt_eq(a: LonLat, b: LonLat) -> bool {
    (a.lon - b.lon).abs() < 1e-9 && (a.lat - b.lat).abs() < 1e-9
}

fn best_outer_for(inner: &[LonLat], polys: &[Polygon]) -> Option<usize> {
    // Pick the smallest-area outer whose bbox contains the inner's
    // bbox. Cheap heuristic; adequate for clean OSM relations.
    let inner_bb = bbox(inner);
    let mut best: Option<(usize, f64)> = None;
    for (i, p) in polys.iter().enumerate() {
        let outer_bb = bbox(&p.outer);
        if outer_bb.0 <= inner_bb.0
            && outer_bb.1 <= inner_bb.1
            && outer_bb.2 >= inner_bb.2
            && outer_bb.3 >= inner_bb.3
        {
            let area = (outer_bb.2 - outer_bb.0) * (outer_bb.3 - outer_bb.1);
            match best {
                None => best = Some((i, area)),
                Some((_, prev)) if area < prev => best = Some((i, area)),
                _ => {}
            }
        }
    }
    best.map(|(i, _)| i)
}

fn bbox(pts: &[LonLat]) -> (f64, f64, f64, f64) {
    let mut min_x = f64::INFINITY;
    let mut min_y = f64::INFINITY;
    let mut max_x = f64::NEG_INFINITY;
    let mut max_y = f64::NEG_INFINITY;
    for p in pts {
        if p.lon < min_x {
            min_x = p.lon;
        }
        if p.lat < min_y {
            min_y = p.lat;
        }
        if p.lon > max_x {
            max_x = p.lon;
        }
        if p.lat > max_y {
            max_y = p.lat;
        }
    }
    (min_x, min_y, max_x, max_y)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_query_relation() {
        let q = build_query("relation/123").unwrap();
        assert!(q.contains("relation(123)"));
        assert!(q.contains("out geom"));
    }

    #[test]
    fn build_query_way() {
        let q = build_query("way/4567").unwrap();
        assert!(q.contains("way(4567)"));
    }

    #[test]
    fn build_query_rejects_garbage() {
        assert!(build_query("foo/bar").is_err());
        assert!(build_query("relation/notnum").is_err());
    }

    #[test]
    fn decode_simple_way_response() {
        let raw = br#"
{ "elements": [
    { "type": "way", "id": 1, "geometry": [
        { "lat": 0.0, "lon": 0.0 },
        { "lat": 1.0, "lon": 0.0 },
        { "lat": 1.0, "lon": 1.0 }
    ]}
]}
"#;
        let g = decode_response(raw, "way/1").unwrap();
        match g {
            Geometry::LineString(pts) => assert_eq!(pts.len(), 3),
            other => panic!("expected linestring, got {other:?}"),
        }
    }

    #[test]
    fn decode_closed_way_as_polygon() {
        let raw = br#"
{ "elements": [
    { "type": "way", "id": 1, "geometry": [
        { "lat": 0.0, "lon": 0.0 },
        { "lat": 1.0, "lon": 0.0 },
        { "lat": 1.0, "lon": 1.0 },
        { "lat": 0.0, "lon": 0.0 }
    ]}
]}
"#;
        let g = decode_response(raw, "way/1").unwrap();
        assert!(matches!(g, Geometry::Polygon { .. }));
    }

    #[test]
    fn decode_simple_relation_with_outer() {
        let raw = br#"
{ "elements": [
    { "type": "relation", "id": 7, "members": [
        { "type": "way", "ref": 1, "role": "outer", "geometry": [
            { "lat": 0.0, "lon": 0.0 },
            { "lat": 1.0, "lon": 0.0 },
            { "lat": 1.0, "lon": 1.0 },
            { "lat": 0.0, "lon": 0.0 }
        ]}
    ]}
]}
"#;
        let g = decode_response(raw, "relation/7").unwrap();
        assert!(matches!(g, Geometry::Polygon { .. }));
    }

    #[test]
    fn query_key_is_stable() {
        let a = query_key("[out:json];relation(1);out geom;");
        let b = query_key("[out:json];relation(1);out geom;");
        assert_eq!(a, b);
        assert_eq!(a.len(), 16);
    }
}
