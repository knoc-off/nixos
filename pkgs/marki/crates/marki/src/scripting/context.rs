//! Lua-accessible render context.
//!
//! Model scripts receive a `ctx` userdata alongside `note`:
//!
//!   * `ctx:render(lang, source)` dispatches one fenced block through the
//!     matching `Renderer` and returns a table `{ front_html, back_html,
//!     assets, meta }`. For `lang = "map"`, the table also gets `map =
//!     { width, height, bbox } ` and `xy(lon, lat) -> x_pct, y_pct`, the
//!     final frame and a coordinate-to-canvas-percentage helper, so a
//!     script can place a pin on the map it just rendered without
//!     reimplementing Marki's projection.
//!   * `ctx:section_html(note, n)` / `ctx:body_html(note)` render a run
//!     of the note's blocks through the shared [`Registry::render_blocks`]
//!     path, so external blocks are dispatched rather than dumped as raw
//!     source.
//!   * `ctx:geo(ref)` looks up any map feature ref (`geo/<name>`,
//!     `relation/N`, `country/DEU`, ...) and returns its
//!     `{ ref, kind, points, bbox = {w,s,e,n}, center = {lon,lat}, bytes }`,
//!     so a model can compute a viewport or a pin position instead of an
//!     author pasting them in by hand.
//!   * `ctx:notes{ model=, tag=, deck= }` returns read-only copies of other
//!     notes in the collection (source-level: tags, headings, sections), so
//!     a note can place itself among others of its kind. Push records that
//!     the note read others, so it can say an update came from a dependency.
//!
//! Assets emitted while a script runs are accumulated here and drained by
//! the sync engine after `generate()` returns.

use marki_render::{Asset, Input};
use mlua::{AnyUserData, LuaSerdeExt, UserData, UserDataMethods};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::note::Note;
use crate::render::Registry;
use crate::scan::ScannedNote;

/// Most notes one `ctx:notes` query may return.
pub const MAX_NOTES_PER_QUERY: usize = 2000;
/// Most `ctx:notes` queries one `generate` call may make.
pub const MAX_NOTE_QUERIES: usize = 16;

/// Every formatted note in the working tree, as `ctx:notes` sees it.
/// Built once per scan; sorted by path.
pub struct NoteIndex {
    notes: Vec<IndexedNote>,
}

struct IndexedNote {
    note: Note,
    /// Path relative to the cards root, `/`-separated.
    rel: String,
    deck: String,
}

impl NoteIndex {
    pub fn new(root: &Path, scanned: &[ScannedNote]) -> Self {
        let mut notes: Vec<IndexedNote> = scanned
            .iter()
            .filter(|sn| sn.note.id.is_some())
            .map(|sn| IndexedNote {
                note: sn.note.clone(),
                rel: sn.path.strip_prefix(root).unwrap_or(&sn.path).to_string_lossy().replace('\\', "/"),
                deck: crate::scan::deck_for_note(root, &sn.note),
            })
            .collect();
        notes.sort_by(|a, b| a.rel.cmp(&b.rel));
        Self { notes }
    }
}

/// A `ctx:notes` filter. At least one field must be set.
#[derive(Default, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct NotesQuery {
    model: Option<String>,
    tag: Option<String>,
    /// Deck prefix on `::` boundaries: `Geo` matches `Geo` and `Geo::Rivers`.
    deck: Option<String>,
}

impl NotesQuery {
    fn matches(&self, n: &IndexedNote) -> bool {
        self.model.as_ref().is_none_or(|m| &n.note.model == m)
            && self.tag.as_ref().is_none_or(|t| n.note.has_tag(t))
            && self.deck.as_ref().is_none_or(|d| {
                n.deck == *d || n.deck.strip_prefix(d.as_str()).is_some_and(|r| r.starts_with("::"))
            })
    }
}

/// The context object passed to model scripts as `ctx`.
#[derive(Clone)]
pub struct RenderContext {
    registry: Arc<Registry>,
    source_path: PathBuf,
    cache_dir: PathBuf,
    /// Assets accumulated during script execution. Shared with every
    /// clone (including the one handed to Lua) so the sync engine can
    /// drain them from its own handle after the script returns.
    accumulated_assets: Arc<Mutex<Vec<Asset>>>,
    index: Option<Arc<NoteIndex>>,
    /// `ctx:notes` calls so far (for the per-generate limit, and so push
    /// knows this note's output depends on other notes).
    note_queries: Arc<Mutex<usize>>,
}

impl RenderContext {
    pub fn new(registry: Arc<Registry>, source_path: PathBuf, cache_dir: PathBuf) -> Self {
        Self {
            registry,
            source_path,
            cache_dir,
            accumulated_assets: Arc::new(Mutex::new(Vec::new())),
            index: None,
            note_queries: Arc::new(Mutex::new(0)),
        }
    }

    /// Give `ctx:notes` a collection to query.
    pub fn with_index(mut self, index: Option<Arc<NoteIndex>>) -> Self {
        self.index = index;
        self
    }

    /// Whether the script read other notes via `ctx:notes`.
    pub fn read_other_notes(&self) -> bool {
        *self.note_queries.lock().unwrap() > 0
    }

    /// Drain all accumulated assets (called after script execution).
    pub fn take_assets(&self) -> Vec<Asset> {
        std::mem::take(&mut self.accumulated_assets.lock().unwrap())
    }

    fn push_assets(&self, assets: Vec<Asset>) {
        if !assets.is_empty() {
            self.accumulated_assets.lock().unwrap().extend(assets);
        }
    }

    fn render_slice(&self, blocks: &[crate::note::Block]) -> String {
        let out = self
            .registry
            .render_blocks(blocks, &self.source_path, &self.cache_dir);
        self.push_assets(out.assets);
        out.html
    }
}

impl UserData for RenderContext {
    fn add_methods<M: UserDataMethods<Self>>(m: &mut M) {
        // ctx:render(lang, source) -> { front_html, back_html, assets, meta[, map, xy] }
        m.add_method("render", |lua, this, (lang, source): (String, String)| {
            let frag = this
                .registry
                .dispatch(&lang, Input::Raw(&source), &this.source_path, &this.cache_dir)
                .map_err(|e| mlua::Error::runtime(format!("render({lang}): {e}")))?;

            let asset_names: Vec<String> =
                frag.assets.iter().map(|a| a.filename.clone()).collect();
            let meta = frag.meta.clone();
            this.push_assets(frag.assets);

            let t = lua.create_table()?;
            t.set("front_html", frag.html)?;
            t.set("back_html", frag.reveal)?;
            t.set("assets", asset_names)?;
            t.set("meta", lua.to_value(&meta)?)?;

            // `map`-specific ergonomics: the final frame, plus xy(lon, lat)
            // -> x_pct, y_pct, so a script can place a pin without
            // reimplementing the projection. Both come from `meta.map`
            // alone (bbox + canvas size), not from marki-map internals.
            if let Some(map) = meta.get("map") {
                t.set("map", lua.to_value(map)?)?;
                let bbox: [f64; 4] = serde_json::from_value(map["bbox"].clone())
                    .map_err(|e| mlua::Error::runtime(format!("render({lang}): bad map.bbox: {e}")))?;
                let center_lon = map["center_lon"].as_f64().unwrap_or(0.0);
                let (w, h) = (map["width"].as_f64().unwrap_or(0.0), map["height"].as_f64().unwrap_or(0.0));
                let bbox = marki_map::geometry::BBox {
                    min_lon: bbox[0],
                    min_lat: bbox[1],
                    max_lon: bbox[2],
                    max_lat: bbox[3],
                };
                let xy = lua.create_function(move |_, (lon, lat): (f64, f64)| {
                    Ok(marki_map::project::xy_percent(bbox, center_lon, w, h, lon, lat))
                })?;
                t.set("xy", xy)?;
            }
            Ok(t)
        });

        // ctx:section_html(note, n) -> string (1-based section index)
        m.add_method("section_html", |_, this, (note, n): (AnyUserData, i64)| {
            let note = note.borrow::<Note>()?;
            let idx = if n >= 1 { (n - 1) as usize } else { return Ok(String::new()) };
            Ok(this.render_slice(note.section(idx)))
        });

        // ctx:body_html(note) -> string
        m.add_method("body_html", |_, this, note: AnyUserData| {
            let note = note.borrow::<Note>()?;
            Ok(this.render_slice(&note.blocks))
        });

        // ctx:geo(ref) -> { ref, kind, points, bbox, center, bytes }
        m.add_method("geo", |lua, this, r: String| {
            let v = this
                .registry
                .call_tool("map", "get", serde_json::json!({"name": r}), &this.source_path, &this.cache_dir)
                .map_err(|e| mlua::Error::runtime(format!("geo({r}): {e}")))?;
            lua.to_value(&v)
        });

        // ctx:notes{ model=, tag=, deck= } -> { note, ... } sorted by path
        m.add_method("notes", |lua, this, filter: mlua::Value| {
            let q: NotesQuery = lua
                .from_value(filter)
                .map_err(|e| mlua::Error::runtime(format!("notes: expected {{ model=, tag=, deck= }}: {e}")))?;
            if q.model.is_none() && q.tag.is_none() && q.deck.is_none() {
                return Err(mlua::Error::runtime("notes: give at least one of model, tag, deck"));
            }
            let index = this.index.as_ref().ok_or_else(|| {
                mlua::Error::runtime("notes: no collection here (single-note preview of an unsaved path?)")
            })?;
            let hits: Vec<&IndexedNote> = index
                .notes
                .iter()
                .filter(|n| n.note.source_path != this.source_path && q.matches(n))
                .collect();
            if hits.len() > MAX_NOTES_PER_QUERY {
                return Err(mlua::Error::runtime(format!(
                    "notes: {} matches, over the limit of {MAX_NOTES_PER_QUERY}; narrow the filter",
                    hits.len()
                )));
            }
            {
                let mut queries = this.note_queries.lock().unwrap();
                *queries += 1;
                if *queries > MAX_NOTE_QUERIES {
                    return Err(mlua::Error::runtime(format!(
                        "notes: more than {MAX_NOTE_QUERIES} queries in one generate(); query once and filter in Lua"
                    )));
                }
            }
            let out = lua.create_table()?;
            for (i, n) in hits.into_iter().enumerate() {
                let ud = lua.create_userdata(n.note.clone())?;
                ud.set_named_user_value("path", n.rel.as_str())?;
                ud.set_named_user_value("deck", n.deck.as_str())?;
                out.raw_set(i + 1, ud)?;
            }
            Ok(out)
        });
    }
}
