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
//!   * Backoff on 429/502/503/504 and transport errors (honours
//!     `Retry-After`, up to 5 attempts)
//!
//! `MARKI_OVERPASS_URL` overrides the interpreter URL (e.g. a
//! self-hosted instance).
//!
//! Failures are converted to [`MapError::Network`] / `Resolve`. The
//! daemon turns each into a card-level failure and continues.

use crate::error::MapError;
use crate::geometry::{best_outer_for, Geometry, LonLat, Polygon};
use serde::Deserialize;
use std::path::Path;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const USER_AGENT: &str = concat!(
    "marki/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/knoc-off/nixos)"
);

const DEFAULT_ENDPOINT: &str = "https://overpass-api.de/api/interpreter";
const HTTP_TIMEOUT: Duration = Duration::from_secs(30);
const MIN_INTERVAL: Duration = Duration::from_millis(1100);

/// Overpass interpreter URL: `MARKI_OVERPASS_URL` (e.g. a self-hosted
/// instance) or the public overpass-api.de.
fn endpoint() -> String {
    std::env::var("MARKI_OVERPASS_URL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| DEFAULT_ENDPOINT.into())
}

/// An error with its whole source chain: reqwest's own Display is just
/// "error sending request", which hides the actual cause.
fn chain(e: &dyn std::error::Error) -> String {
    let mut s = e.to_string();
    let mut src = e.source();
    while let Some(c) = src {
        s.push_str(": ");
        s.push_str(&c.to_string());
        src = c.source();
    }
    s
}

/// Seconds from a `Retry-After` header (delta-seconds form only), capped
/// so one bad header can't stall a render for minutes.
fn retry_after(resp: &reqwest::blocking::Response) -> Option<Duration> {
    let secs: u64 = resp.headers().get(reqwest::header::RETRY_AFTER)?.to_str().ok()?.trim().parse().ok()?;
    Some(Duration::from_secs(secs.min(60)))
}

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
        let tmp = cache_file.with_extension(format!("{}.tmp", crate::cache::tmp_suffix()));
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

/// POST a query to Overpass, retrying 429/502/503/504 and transport errors
/// with backoff (honouring `Retry-After`). The final error names the
/// endpoint, the last status or cause, and how long it tried.
fn http_post(ql: &str) -> Result<Vec<u8>, MapError> {
    let url = endpoint();
    let client = reqwest::blocking::Client::builder()
        .timeout(HTTP_TIMEOUT)
        .user_agent(USER_AGENT)
        .build()
        .map_err(|e| MapError::Network(format!("client: {}", chain(&e))))?;

    let mut backoff = Duration::from_secs(2);
    let max_backoff = Duration::from_secs(30);
    let max_attempts = 5;
    let started = Instant::now();
    let mut last = String::new();

    for attempt in 1..=max_attempts {
        rate_limit();
        let wait = match client.post(&url).body(ql.to_string()).send() {
            Ok(resp) => {
                let status = resp.status();
                if status.is_success() {
                    return resp
                        .bytes()
                        .map(|b| b.to_vec())
                        .map_err(|e| MapError::Network(format!("overpass read ({url}): {}", chain(&e))));
                }
                let hint = retry_after(&resp);
                last = match hint {
                    Some(d) => format!("HTTP {status} (retry after {}s)", d.as_secs()),
                    None => format!("HTTP {status}"),
                };
                if !matches!(status.as_u16(), 429 | 502 | 503 | 504) {
                    // A 400 page carries Overpass's complaint about the query.
                    let body = strip_tags(&resp.text().unwrap_or_default());
                    let msg = body.find("Error").map_or(&body[..], |i| &body[i..]);
                    return Err(MapError::Network(format!(
                        "overpass ({url}): {last}: {}",
                        msg.chars().take(300).collect::<String>()
                    )));
                }
                hint.unwrap_or(backoff)
            }
            Err(e) => {
                last = chain(&e);
                backoff
            }
        };
        if attempt == max_attempts {
            break;
        }
        tracing::warn!("overpass {last}; attempt {attempt}/{max_attempts}, retrying in {wait:?}");
        std::thread::sleep(wait);
        backoff = (backoff * 2).min(max_backoff);
    }
    Err(MapError::Network(format!(
        "overpass ({url}): {last}; gave up after {max_attempts} attempts over {}s. \
         The public server rate-limits heavy use: wait a minute and retry (responses are cached), \
         or point MARKI_OVERPASS_URL at another instance",
        started.elapsed().as_secs()
    )))
}

fn strip_tags(s: &str) -> String {
    let mut out = String::new();
    let mut in_tag = false;
    for c in s.chars() {
        match c {
            '<' => in_tag = true,
            '>' => in_tag = false,
            c if !in_tag => out.push(c),
            _ => {}
        }
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
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

const NOMINATIM: &str = "https://nominatim.openstreetmap.org/search";

/// Search OSM by name via Nominatim. Each hit carries a ready map ref
/// (`relation/N`, `way/N`; nodes are points and not map features).
/// Cached like Overpass responses; shares the 1 req/s limit, which is
/// also Nominatim's usage policy.
pub fn search(query: &str, cache_root: &Path) -> Result<Vec<serde_json::Value>, MapError> {
    let cache_dir = cache_root.join("net").join("nominatim");
    std::fs::create_dir_all(&cache_dir)?;
    let cache_file = cache_dir.join(format!("{}.json", query_key(query)));
    let raw = if cache_file.exists() {
        std::fs::read(&cache_file)?
    } else {
        rate_limit();
        let url = reqwest::Url::parse_with_params(
            NOMINATIM,
            &[("q", query), ("format", "jsonv2"), ("limit", "10"), ("accept-language", "en")],
        )
        .map_err(|e| MapError::Network(format!("nominatim url: {e}")))?;
        let resp = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(10))
            .user_agent(USER_AGENT)
            .build()
            .map_err(|e| MapError::Network(format!("client: {}", chain(&e))))?
            .get(url)
            .send()
            .map_err(|e| MapError::Network(format!("nominatim: {}", chain(&e))))?;
        let status = resp.status();
        if !status.is_success() {
            let hint = retry_after(&resp).map(|d| format!(" (retry after {}s)", d.as_secs())).unwrap_or_default();
            return Err(MapError::Network(format!("nominatim: HTTP {status}{hint}")));
        }
        let bytes = resp.bytes().map_err(|e| MapError::Network(format!("nominatim: {}", chain(&e))))?.to_vec();
        let tmp = cache_file.with_extension(format!("{}.tmp", crate::cache::tmp_suffix()));
        std::fs::write(&tmp, &bytes)?;
        std::fs::rename(&tmp, &cache_file)?;
        bytes
    };
    decode_search(&raw)
}

fn decode_search(raw: &[u8]) -> Result<Vec<serde_json::Value>, MapError> {
    let hits: Vec<serde_json::Value> =
        serde_json::from_slice(raw).map_err(|e| MapError::Resolve(format!("nominatim json: {e}")))?;
    Ok(hits
        .iter()
        .filter_map(|h| {
            let kind = h["osm_type"].as_str()?;
            if kind == "node" {
                return None;
            }
            Some(serde_json::json!({
                "ref": format!("{kind}/{}", h["osm_id"].as_i64()?),
                "name": h["display_name"],
                "kind": format!("{}={}", h["category"].as_str().unwrap_or("?"), h["type"].as_str().unwrap_or("?")),
            }))
        })
        .collect())
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

/// Run an author's Overpass selection (ways/relations only, bbox
/// required) and merge every hit into one geometry. The statement is
/// wrapped: `[out:json][timeout:60][maxsize:64Mi];(<stmt>);out geom;`.
pub fn query(stmt: &str, cache_root: &Path) -> Result<Geometry, MapError> {
    let stmt = check_selector(stmt)?;
    if !has_own_bbox(stmt) {
        return Err(MapError::Resolve(
            "overpass: add a bounding box (south,west,north,east), e.g. way[name=\"X\"](30,95,45,125)".into(),
        ));
    }
    decode_all(&run_ql(&format!("[out:json][timeout:60][maxsize:67108864];({stmt};);out geom;"), cache_root)?)
}

/// Run an author's Overpass selection with no bbox of its own inside a
/// caller-supplied frame (`[viewport]`'s fixed frame, for a per-layer
/// `osm = "<selector>"` fetched for the map's own area). Rejects a
/// selector that already carries a bbox, since the two would combine
/// unpredictably (Overpass ANDs sequential filters).
pub fn query_in_bbox(stmt: &str, bbox: (f64, f64, f64, f64), cache_root: &Path) -> Result<Geometry, MapError> {
    let stmt = check_selector(stmt)?;
    if has_own_bbox(stmt) {
        return Err(MapError::Resolve(
            "osm: give only the selector, e.g. way[highway~\"^(primary|secondary)$\"]; \
             the map's frame supplies the bounding box"
                .into(),
        ));
    }
    let (s, w, n, e) = bbox;
    let ql = format!("[out:json][timeout:60][maxsize:67108864];({stmt}({s},{w},{n},{e}););out geom;");
    decode_all(&run_ql(&ql, cache_root)?)
}

/// Shared validation for an author-supplied Overpass selector (used by
/// both `query` and `query_in_bbox`): trims the trailing `;`, rejects an
/// embedded output statement (`out ...`/`out;`) since that part is
/// always added for the caller, and requires a `way`/`relation`/`nwr`
/// selection.
fn check_selector(stmt: &str) -> Result<&str, MapError> {
    let stmt = stmt.trim().trim_end_matches(';');
    let lower = stmt.to_lowercase();
    if lower.contains("[out:") || lower.contains("out ") || lower.contains("out;") {
        return Err(MapError::Resolve(
            "overpass: give only the selection, e.g. way[name=\"X\"](s,w,n,e); the output part is added".into(),
        ));
    }
    if !(lower.starts_with("way") || lower.starts_with("relation") || lower.starts_with("nwr")) {
        return Err(MapError::Resolve("overpass: select way[...] or relation[...]".into()));
    }
    Ok(stmt)
}

/// Whether `stmt` already has a `(area...)` or a `(s,w,n,e)` bbox filter.
fn has_own_bbox(stmt: &str) -> bool {
    stmt.contains("(area")
        || stmt
            .split(['(', ')'])
            .skip(1)
            .step_by(2)
            .any(|inner| inner.split(',').count() == 4 && inner.split(',').all(|n| n.trim().parse::<f64>().is_ok()))
}

/// Run a fully-built Overpass QL query through the content-addressed
/// cache, fetching over the network only on a miss.
fn run_ql(ql: &str, cache_root: &Path) -> Result<Vec<u8>, MapError> {
    let cache_dir = cache_root.join("net").join("overpass");
    std::fs::create_dir_all(&cache_dir)?;
    let cache_file = cache_dir.join(format!("{}.json", query_key(ql)));
    if cache_file.exists() {
        return Ok(std::fs::read(&cache_file)?);
    }
    let bytes = http_post(ql)?;
    let tmp = cache_file.with_extension(format!("{}.tmp", crate::cache::tmp_suffix()));
    std::fs::write(&tmp, &bytes)?;
    std::fs::rename(&tmp, &cache_file)?;
    Ok(bytes)
}

/// Every way/relation in a response, merged (areas or lines, not both).
fn decode_all(raw: &[u8]) -> Result<Geometry, MapError> {
    let parsed: OverpassResponse =
        serde_json::from_slice(raw).map_err(|e| MapError::Resolve(format!("overpass json: {e}")))?;
    let mut polys: Vec<Polygon> = Vec::new();
    let mut lines: Vec<Vec<LonLat>> = Vec::new();
    for el in parsed.elements {
        let one = OverpassResponse { elements: vec![el] };
        let g = match &one.elements[0] {
            OverpassElement::Way { .. } => decode_way(&one, "way"),
            OverpassElement::Relation { .. } => decode_relation(&one, "relation"),
            OverpassElement::Node(_) => continue,
        };
        match g? {
            Geometry::Polygon { outer, holes } => polys.push(Polygon { outer, holes }),
            Geometry::MultiPolygon(ps) => polys.extend(ps),
            Geometry::LineString(l) => lines.push(l),
            Geometry::MultiLineString(ls) => lines.extend(ls),
            Geometry::Point(_) => {}
        }
    }
    match (polys.is_empty(), lines.is_empty()) {
        (true, true) => Err(MapError::Resolve("overpass: the query matched nothing (check tags, names and bbox)".into())),
        (false, true) => Ok(Geometry::MultiPolygon(polys)),
        (true, false) => Ok(Geometry::MultiLineString(lines)),
        // A wall's closed loops (forts) come back as areas: keep them as outlines.
        (false, false) => {
            lines.extend(polys.into_iter().map(|p| p.outer));
            Ok(Geometry::MultiLineString(lines))
        }
    }
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

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /// `MARKI_OVERPASS_URL` is process-global; any test (in this module
    /// or `pipeline`'s) that points it at a fake server must hold this
    /// for the duration, or a parallel test's real value/removal races it.
    pub(crate) static ENV_LOCK: Mutex<()> = Mutex::new(());

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
    fn query_needs_selection_and_bbox() {
        let d = std::env::temp_dir();
        for (q, want) in [
            ("[out:json];way(1);out geom;", "only the selection"),
            ("node[name=x](1,2,3,4)", "select way"),
            ("way[name=\"Great Wall\"]", "bounding box"),
        ] {
            let e = query(q, &d).unwrap_err().to_string();
            assert!(e.contains(want), "{q}: {e}");
        }
    }

    #[test]
    fn decode_all_merges_ways_and_keeps_loops_as_lines() {
        let raw = br#"{"elements":[
          {"type":"way","geometry":[{"lat":40,"lon":100},{"lat":40.5,"lon":101}]},
          {"type":"way","geometry":[{"lat":41,"lon":102},{"lat":41,"lon":103},{"lat":41.5,"lon":103},{"lat":41,"lon":102}]},
          {"type":"node","lat":1,"lon":2}
        ]}"#;
        match decode_all(raw).unwrap() {
            Geometry::MultiLineString(ls) => assert_eq!(ls.len(), 2),
            g => panic!("{g:?}"),
        }
        assert!(decode_all(br#"{"elements":[]}"#).unwrap_err().to_string().contains("matched nothing"));
    }

    #[test]
    fn search_hits_become_map_refs() {
        let raw = br#"[
          {"osm_type":"way","osm_id":188317625,"category":"historic","type":"citywalls","display_name":"Great Wall"},
          {"osm_type":"node","osm_id":1,"category":"place","type":"city","display_name":"a point"},
          {"osm_type":"relation","osm_id":2145268,"category":"boundary","type":"administrative","display_name":"Bavaria"}
        ]"#;
        let hits = decode_search(raw).unwrap();
        let refs: Vec<_> = hits.iter().map(|h| h["ref"].as_str().unwrap()).collect();
        assert_eq!(refs, ["way/188317625", "relation/2145268"]);
        assert_eq!(hits[0]["kind"], "historic=citywalls");
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

    /// Serve one raw HTTP response per connection: `(status line + headers, body)`.
    pub(crate) fn fake_server(responses: Vec<(&'static str, &'static str)>) -> String {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/api/interpreter", l.local_addr().unwrap());
        std::thread::spawn(move || {
            use std::io::{Read, Write};
            for (head, body) in responses {
                let (mut s, _) = l.accept().unwrap();
                let mut buf = [0u8; 4096];
                let _ = s.read(&mut buf);
                let r = format!("{head}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len());
                let _ = s.write_all(r.as_bytes());
            }
        });
        url
    }

    #[test]
    fn rate_limit_is_retried_and_a_bad_query_explains_itself() {
        let _guard = ENV_LOCK.lock().unwrap();
        let url = fake_server(vec![
            ("HTTP/1.1 429 Too Many Requests\r\nRetry-After: 1", ""),
            ("HTTP/1.1 200 OK", "{\"elements\":[]}"),
            ("HTTP/1.1 400 Bad Request", "<p><strong>Error</strong>: line 1: parse error: ';' expected </p>\n"),
        ]);
        // SAFETY: only this test touches the variable while holding ENV_LOCK.
        unsafe { std::env::set_var("MARKI_OVERPASS_URL", &url) };
        assert_eq!(http_post("q").unwrap(), b"{\"elements\":[]}");
        let e = http_post("q").unwrap_err().to_string();
        assert!(e.contains("HTTP 400") && e.contains("parse error: ';' expected") && e.contains(&url), "{e}");
        unsafe { std::env::remove_var("MARKI_OVERPASS_URL") };
    }

    #[test]
    fn query_in_bbox_rejects_a_selectors_own_bbox_and_query_requires_one() {
        // A selector with its own bbox is for `query` (a saved feature),
        // not `query_in_bbox` (a per-layer osm fetch inside the map's
        // own frame) -- the two would otherwise combine unpredictably.
        let d = std::env::temp_dir().join(format!("marki-osm-{}-{:?}", std::process::id(), std::thread::current().id()));
        let own_bbox = "way[highway](30,95,45,125)";
        assert!(query_in_bbox(own_bbox, (30.0, 95.0, 45.0, 125.0), &d).unwrap_err().to_string().contains("map's frame supplies"));
        assert!(query("way[highway]", &d).unwrap_err().to_string().contains("bounding box"));
        assert!(query("select foo", &d).unwrap_err().to_string().contains("select way"));
        assert!(query("way[highway](30,95,45,125); out geom;", &d).unwrap_err().to_string().contains("output part"));    }
}
