//! A local index of every note's title and ancestor path, built from one
//! bulk ETAPI fetch (`Client::all_notes`) and kept warm across restarts on
//! disk.
//!
//! This exists because the note-link picker needs multi-token path search
//! ("work proj alpha" -> Work > Projects > Alpha), which needs the whole
//! tree in memory to walk -- no single ETAPI query returns that, and
//! `blink.cmp`'s inline `[[` completion can't reach it anyway (a space
//! closes blink's completion menu, so multi-token queries only work in a
//! picker, not inline; see `lua/rhizome/init.lua`'s picker wiring).
//!
//! At ~500 notes a bulk fetch is instant, so this deliberately does not
//! chase incremental sync: a full `replace` on refresh, `upsert`/`remove`
//! for the handful of operations rhizome itself performs (rename, create,
//! delete), and a disk cache so a restart isn't a cold start.

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use rhizome_etapi::{Attribute, Note};
use serde::{Deserialize, Serialize};

use crate::meta::{Kind, is_system_relation};

/// Just enough about a note to place it in the tree. Not a content cache --
/// see `rhizomed::rendered` for that.
///
/// `attributes` rides along on the same bulk fetch that builds the tree --
/// `Client::all_notes` already returns every note's attributes, so keeping
/// them here costs nothing extra over the network and is what makes
/// `definitions_for` and `vocabulary` possible without a second fetch.
/// `#[serde(default)]` lets a cache written before this field existed
/// deserialize as an empty vector instead of failing to load at all.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entry {
    pub title: String,
    pub parent_note_ids: Vec<String>,
    #[serde(default)]
    pub attributes: Vec<Attribute>,
    /// Trilium's own ordering of this note's children, for `children` to
    /// sort by. `#[serde(default)]` for the same reason as `attributes`: a
    /// cache written before this field existed should still load, just
    /// browsed alphabetically until the next refresh fills it in.
    #[serde(default)]
    pub child_note_ids: Vec<String>,
}

/// A note ready for display in a picker: its own title plus the titles of
/// its ancestors, root excluded.
#[derive(Debug, Clone, PartialEq)]
pub struct Listed {
    pub note_id: String,
    pub title: String,
    pub path: Vec<String>,
}

/// Ancestors from (excluding) root down to (excluding) `note_id` itself, as
/// `(note_id, title)` pairs. A note cloned into several places has more than
/// one `parent_note_ids` entry; this always follows the first, so a picker
/// built from `list` shows one path per note rather than fanning a clone out
/// into duplicates. `browse` (see `rhizome/children`) uses this same
/// first-parent trail to seed a drill-down stack when entering a note
/// directly (`:Rhizome browse .`/`..`/`<noteId>`) rather than walking down
/// from root -- an ancestor path is unambiguous even though the note itself
/// may have several.
pub fn resolve_trail(notes: &HashMap<String, Entry>, note_id: &str) -> Vec<(String, String)> {
    let mut trail = Vec::new();
    let mut current = note_id.to_string();
    let mut seen = HashSet::new();
    while seen.insert(current.clone()) {
        let Some(entry) = notes.get(&current) else {
            break;
        };
        let Some(parent_id) = entry.parent_note_ids.first() else {
            break;
        };
        if parent_id == "root" {
            break;
        }
        let Some(parent) = notes.get(parent_id) else {
            break;
        };
        trail.push((parent_id.clone(), parent.title.clone()));
        current = parent_id.clone();
    }
    trail.reverse();
    trail
}

/// Titles from (excluding) root down to (excluding) `note_id` itself. See
/// `resolve_trail`, which this is a thin projection of.
pub fn resolve_path(notes: &HashMap<String, Entry>, note_id: &str) -> Vec<String> {
    resolve_trail(notes, note_id)
        .into_iter()
        .map(|(_, title)| title)
        .collect()
}

/// Every note in `notes`, each with its resolved ancestor path.
pub fn list(notes: &HashMap<String, Entry>) -> Vec<Listed> {
    notes
        .iter()
        .map(|(note_id, entry)| Listed {
            note_id: note_id.clone(),
            title: entry.title.clone(),
            path: resolve_path(notes, note_id),
        })
        .collect()
}

/// One note, with its resolved ancestor path -- the single-note form of
/// `list`, for a caller (relation-value completion) that only needs one
/// note's display form rather than the whole vault's.
pub fn listed(notes: &HashMap<String, Entry>, note_id: &str) -> Option<Listed> {
    let entry = notes.get(note_id)?;
    Some(Listed {
        note_id: note_id.to_string(),
        title: entry.title.clone(),
        path: resolve_path(notes, note_id),
    })
}

/// A note as it appears one level down from its parent in `children`.
#[derive(Debug, Clone, PartialEq)]
pub struct Child {
    pub note_id: String,
    pub title: String,
    /// How many notes list this one as a parent (its own child count),
    /// for a drill-down UI to show an expand affordance without a second
    /// round trip.
    pub child_count: usize,
    /// How many parents this note has. `1` for an ordinary note; `> 1`
    /// means it is a clone, and it will appear once under each parent that
    /// lists it, faithfully mirroring Trilium's own tree rather than
    /// picking one (as `resolve_path` does for the flat picker).
    pub clone_count: usize,
    /// Whether this note carries `#archived`. Trilium's own tree hides
    /// archived notes by default; `children` still returns them (this is
    /// the read used by `browse`, which offers its own show/hide toggle)
    /// rather than baking the default in here.
    pub archived: bool,
}

/// Every note that lists `note_id` as a parent, in Trilium's own child
/// order (`Entry::child_note_ids`) where known, alphabetical by title
/// after -- so a note added by `Index::upsert`, which does not touch its
/// parent's `child_note_ids` until the next full refresh, still shows up
/// immediately rather than waiting on a round trip.
///
/// A single pass over every entry, rather than one lookup per candidate:
/// each entry's `parent_note_ids` is walked once to both collect matches
/// against `note_id` and tally every note's own child count (how many
/// other notes list it as a parent), which a second pass over every note
/// would otherwise cost.
pub fn children(notes: &HashMap<String, Entry>, note_id: &str) -> Vec<Child> {
    let mut child_counts: HashMap<&str, usize> = HashMap::new();
    let mut matches: Vec<(&String, &Entry)> = Vec::new();
    for (id, entry) in notes {
        for parent in &entry.parent_note_ids {
            *child_counts.entry(parent.as_str()).or_insert(0) += 1;
        }
        if entry.parent_note_ids.iter().any(|p| p == note_id) {
            matches.push((id, entry));
        }
    }

    let order: HashMap<&str, usize> = notes
        .get(note_id)
        .map(|parent| {
            parent
                .child_note_ids
                .iter()
                .enumerate()
                .map(|(i, id)| (id.as_str(), i))
                .collect()
        })
        .unwrap_or_default();

    matches.sort_by(|(id_a, entry_a), (id_b, entry_b)| {
        let position = |id: &str| order.get(id).copied();
        match (position(id_a), position(id_b)) {
            (Some(a), Some(b)) => a.cmp(&b),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => entry_a.title.cmp(&entry_b.title),
        }
    });

    matches
        .into_iter()
        .map(|(id, entry)| Child {
            note_id: id.clone(),
            title: entry.title.clone(),
            child_count: child_counts.get(id.as_str()).copied().unwrap_or(0),
            clone_count: entry.parent_note_ids.len(),
            archived: entry
                .attributes
                .iter()
                .any(|a| a.is_label() && a.name == "archived"),
        })
        .collect()
}

/// `note_id`'s own immediate parents, as `(note_id, title)` pairs -- the
/// reverse of `children`. For a note with more than one (a clone), this is
/// what lets a caller (a buffer-bound move/unlink command, which has no
/// drill-down stack to read "the parent" off of) ask the user which
/// placement they mean before acting.
pub fn parents(notes: &HashMap<String, Entry>, note_id: &str) -> Vec<(String, String)> {
    let Some(entry) = notes.get(note_id) else {
        return Vec::new();
    };
    entry
        .parent_note_ids
        .iter()
        .map(|id| {
            let title = notes
                .get(id)
                .map(|parent| parent.title.clone())
                .unwrap_or_else(|| id.clone());
            (id.clone(), title)
        })
        .collect()
}

/// A `label:foo`/`relation:foo` definition attribute's value, parsed. Trilium
/// writes this as a comma-separated token string (`promoted,single,text`) --
/// see `promoted_attribute_definition_parser.ts` upstream, which this
/// mirrors. Unrecognised tokens are ignored rather than rejected: an older
/// or newer Trilium version's definition should degrade, not break
/// completion for every note under it.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Definition {
    pub promoted: bool,
    pub multi: bool,
    pub label_type: Option<String>,
}

const LABEL_TYPES: &[&str] = &[
    "text", "textarea", "number", "boolean", "date", "datetime", "time", "url", "color",
];

fn parse_definition(value: &str) -> Definition {
    let mut def = Definition::default();
    for token in value.split(',').map(str::trim) {
        match token {
            "promoted" => def.promoted = true,
            "single" => def.multi = false,
            "multi" => def.multi = true,
            t if LABEL_TYPES.contains(&t) => def.label_type = Some(t.to_string()),
            _ => {}
        }
    }
    def
}

/// Definition attributes in effect for `note_id`: its own `label:*`/
/// `relation:*` labels, plus any inherited from ancestors (these definition
/// labels are themselves inheritable in Trilium, so a definition declared
/// once on a folder note applies to everything under it). A note's own
/// definition wins over an ancestor's for the same name, matching Trilium's
/// own closest-wins inheritance rule.
pub fn definitions_for(
    notes: &HashMap<String, Entry>,
    note_id: &str,
) -> HashMap<(Kind, String), Definition> {
    let mut found = HashMap::new();
    let mut current = note_id.to_string();
    let mut seen = HashSet::new();
    while seen.insert(current.clone()) {
        let Some(entry) = notes.get(&current) else {
            break;
        };
        for attribute in &entry.attributes {
            if !attribute.is_label() {
                continue;
            }
            if let Some(name) = attribute.name.strip_prefix("label:") {
                found
                    .entry((Kind::Label, name.to_string()))
                    .or_insert_with(|| parse_definition(&attribute.value));
            } else if let Some(name) = attribute.name.strip_prefix("relation:") {
                found
                    .entry((Kind::Relation, name.to_string()))
                    .or_insert_with(|| parse_definition(&attribute.value));
            }
        }
        let Some(parent_id) = entry.parent_note_ids.first() else {
            break;
        };
        if parent_id == "root" {
            break;
        }
        current = parent_id.clone();
    }
    found
}

/// Every ordinary (non-system, non-definition) label and relation name used
/// anywhere in the vault, with the distinct values observed for each --
/// completion for an attribute that has no `label:`/`relation:` definition
/// at all, which is most of them in practice.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Vocabulary {
    pub label_names: Vec<String>,
    pub relation_names: Vec<String>,
    pub values: HashMap<(Kind, String), Vec<String>>,
}

pub fn vocabulary(notes: &HashMap<String, Entry>) -> Vocabulary {
    let mut label_names: Vec<String> = Vec::new();
    let mut relation_names: Vec<String> = Vec::new();
    let mut values: HashMap<(Kind, String), Vec<String>> = HashMap::new();

    for entry in notes.values() {
        for attribute in &entry.attributes {
            if is_system_relation(attribute)
                || attribute.name.starts_with("label:")
                || attribute.name.starts_with("relation:")
            {
                continue;
            }
            let kind = if attribute.is_relation() {
                Kind::Relation
            } else {
                Kind::Label
            };
            let names = match kind {
                Kind::Label => &mut label_names,
                Kind::Relation => &mut relation_names,
            };
            if !names.iter().any(|n| n == &attribute.name) {
                names.push(attribute.name.clone());
            }
            if !attribute.value.is_empty() {
                let bucket = values.entry((kind, attribute.name.clone())).or_default();
                if !bucket.iter().any(|v| v == &attribute.value) {
                    bucket.push(attribute.value.clone());
                }
            }
        }
    }
    label_names.sort();
    relation_names.sort();
    Vocabulary {
        label_names,
        relation_names,
        values,
    }
}

/// Notes matching `query`, best match first.
///
/// `query` is matched as a sequence of word-prefixes against the note's own
/// title *and* its ancestor path, in order, with no separator required --
/// "waystonepeople" and "waystone-people" both match a note filed under
/// Waystone > People, and "waypeoplejohn" matches John Doe filed there,
/// without needing to type any of "Waystone", "People" or "John" in full.
/// This is what makes a query useful inline, where `blink.cmp` only ever
/// sees one token: multi-word path search elsewhere in this codebase (the
/// picker) can rely on a literal space between words, but that space closes
/// blink's own completion menu, so this is the only way for `[[` to find a
/// note by more of its path than "does it contain this substring".
///
/// The ranking only has to be good enough to order equally-scored
/// candidates: the LSP client re-scores every item itself (`filterText`
/// carries the same path, compacted the same way), so this does not need to
/// be a real fuzzy matcher -- just complete and not too eager to exclude.
pub fn search(notes: &HashMap<String, Entry>, query: &str, limit: usize) -> Vec<Listed> {
    let query = compact(query);
    if query.is_empty() {
        return Vec::new();
    }
    let mut scored: Vec<(u8, usize, Listed)> = list(notes)
        .into_iter()
        .filter_map(|listed| {
            let rank = rank(&listed, &query)?;
            let depth = listed.path.len();
            Some((rank, depth, listed))
        })
        .collect();
    scored.sort_by(|(a_rank, a_depth, a), (b_rank, b_depth, b)| {
        a_rank
            .cmp(b_rank)
            .then_with(|| a_depth.cmp(b_depth))
            .then_with(|| a.title.len().cmp(&b.title.len()))
            .then_with(|| a.note_id.cmp(&b.note_id))
    });
    scored.truncate(limit);
    scored.into_iter().map(|(_, _, listed)| listed).collect()
}

/// `text`, lowercased with everything that is not a letter or digit dropped
/// -- the same reduction applied to a query and to a title before comparing
/// them, so "Waystone/People", "waystone-people" and "waystonepeople" are
/// all the same string once compared.
fn compact(text: &str) -> String {
    text.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(|c| c.to_lowercase())
        .collect()
}

/// `text` split into lowercased, alphanumeric-only words: "Alice Smith" ->
/// `["alice", "smith"]`. The unit a path-prefix match advances one at a
/// time -- see `path_match`.
fn words(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(|w| w.to_lowercase())
        .collect()
}

/// Every word of `listed`'s ancestor titles, in path order, followed by
/// every word of its own title -- the sequence `path_match` walks -- along
/// with the index at which the note's own title begins (everything before
/// that index came only from an ancestor).
fn match_units(listed: &Listed) -> (Vec<String>, usize) {
    let mut units = Vec::new();
    for ancestor in &listed.path {
        units.extend(words(ancestor));
    }
    let title_start = units.len();
    units.extend(words(&listed.title));
    (units, title_start)
}

/// `0` if `query` names `listed`'s title outright, `1` if it is a literal
/// prefix of it, `2` if a path-prefix match reaches into the title (an
/// abbreviation, or a query that also names some of the path), `3` if it
/// only ever reaches into the ancestor path, `None` if it matches nothing
/// at all.
fn rank(listed: &Listed, query: &str) -> Option<u8> {
    let title = compact(&listed.title);
    if title == query {
        return Some(0);
    }
    if title.starts_with(query) {
        return Some(1);
    }
    let (units, title_start) = match_units(listed);
    let last_unit = path_match(&units, query)?;
    Some(if last_unit >= title_start { 2 } else { 3 })
}

/// Can `query` be split into consecutive, non-empty chunks, each a prefix of
/// a distinct `units` entry, with those entries used in increasing order?
/// Returns the index of the last unit used, if so.
///
/// This is what lets "waystonepeople" match a note under Waystone > People
/// without a separator, and "waypeoplejohn" match one under Waystone >
/// People titled "John Doe" -- each piece just has to be a prefix of the
/// next not-yet-used unit, not a whole word.
///
/// Tracked as the minimal unit index able to account for each prefix of
/// `query`: a smaller index always leaves at least as many later units
/// available for the rest of the query as a larger one would, so it
/// dominates every other way of reaching that same prefix and is the only
/// one worth keeping.
fn path_match(units: &[String], query: &str) -> Option<usize> {
    if query.is_empty() {
        return None;
    }
    let query: Vec<char> = query.chars().collect();
    // `dp[i]` is one more than the index of the last unit used to account
    // for `query[..i]` (so `0` means "no unit used yet", since a plain
    // index has no room for that) -- `None` means that prefix is not
    // reachable at all.
    let mut dp: Vec<Option<usize>> = vec![None; query.len() + 1];
    dp[0] = Some(0);
    for i in 0..query.len() {
        let Some(last) = dp[i] else { continue };
        for (unit_idx, unit) in units.iter().enumerate().skip(last) {
            let overlap = query[i..]
                .iter()
                .zip(unit.chars())
                .take_while(|(a, b)| **a == *b)
                .count();
            if overlap == 0 {
                continue;
            }
            let next = i + overlap;
            let candidate = unit_idx + 1;
            if dp[next].is_none_or(|current| candidate < current) {
                dp[next] = Some(candidate);
            }
        }
    }
    dp[query.len()].map(|shifted| shifted - 1)
}

/// `$XDG_CACHE_HOME/rhizome/<host>.json`, falling back to `$HOME/.cache`.
/// `None` if neither is set (e.g. a minimal container) -- the index still
/// works without a cache, it just always starts cold.
pub fn cache_path(base_url: &str) -> Option<PathBuf> {
    let cache_home = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))?;
    Some(
        cache_home
            .join("rhizome")
            .join(format!("{}.json", sanitize_host(base_url))),
    )
}

/// `base_url` reduced to a filesystem-safe fragment: scheme stripped,
/// anything that isn't alphanumeric/`.`/`-` replaced with `_`. Keeps a
/// separate cache per Trilium server without needing a subdirectory per
/// host.
fn sanitize_host(base_url: &str) -> String {
    base_url
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '.' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

/// The shared, thread-safe index. Cheap to clone (an `Arc` underneath), so
/// the background refresh thread and the LSP loop can each hold one.
#[derive(Clone)]
pub struct Index {
    notes: Arc<RwLock<HashMap<String, Entry>>>,
    cache_path: Option<PathBuf>,
}

impl Index {
    /// Loads whatever is on disk at `cache_path` synchronously (small, and
    /// this runs before the LSP loop starts serving requests), leaving a
    /// background thread to call `replace` with fresh data once it lands.
    pub fn new(cache_path: Option<PathBuf>) -> Self {
        let notes = cache_path
            .as_deref()
            .and_then(load_cache)
            .unwrap_or_default();
        Self {
            notes: Arc::new(RwLock::new(notes)),
            cache_path,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.notes.read().expect("index lock poisoned").is_empty()
    }

    pub fn len(&self) -> usize {
        self.notes.read().expect("index lock poisoned").len()
    }

    pub fn list(&self) -> Vec<Listed> {
        list(&self.notes.read().expect("index lock poisoned"))
    }

    pub fn search(&self, query: &str, limit: usize) -> Vec<Listed> {
        search(
            &self.notes.read().expect("index lock poisoned"),
            query,
            limit,
        )
    }

    pub fn get(&self, note_id: &str) -> Option<Entry> {
        self.notes
            .read()
            .expect("index lock poisoned")
            .get(note_id)
            .cloned()
    }

    /// See the free function of the same name.
    pub fn listed(&self, note_id: &str) -> Option<Listed> {
        listed(&self.notes.read().expect("index lock poisoned"), note_id)
    }

    /// See `resolve_trail`.
    pub fn trail(&self, note_id: &str) -> Vec<(String, String)> {
        resolve_trail(&self.notes.read().expect("index lock poisoned"), note_id)
    }

    /// See the free function of the same name.
    pub fn children(&self, note_id: &str) -> Vec<Child> {
        children(&self.notes.read().expect("index lock poisoned"), note_id)
    }

    /// See the free function of the same name.
    pub fn parents(&self, note_id: &str) -> Vec<(String, String)> {
        parents(&self.notes.read().expect("index lock poisoned"), note_id)
    }

    /// Definition attributes (`label:foo`, `relation:foo`) in effect for
    /// `note_id`, own and inherited. See the free function of the same name.
    pub fn definitions_for(&self, note_id: &str) -> HashMap<(Kind, String), Definition> {
        definitions_for(&self.notes.read().expect("index lock poisoned"), note_id)
    }

    /// Every ordinary label/relation name and observed value in the vault.
    /// See the free function of the same name.
    pub fn vocabulary(&self) -> Vocabulary {
        vocabulary(&self.notes.read().expect("index lock poisoned"))
    }

    /// Replace the whole index -- the background refresh's result, or the
    /// initial fetch on an empty cache.
    pub fn replace(&self, fetched: Vec<Note>) {
        let map = fetched
            .into_iter()
            .map(|note| {
                (
                    note.note_id,
                    Entry {
                        title: note.title,
                        parent_note_ids: note.parent_note_ids,
                        attributes: note.attributes,
                        child_note_ids: note.child_note_ids,
                    },
                )
            })
            .collect();
        *self.notes.write().expect("index lock poisoned") = map;
        self.persist();
    }

    /// Reflect a single create/rename in the index without waiting for the
    /// next full refresh -- rhizome always knows the new state of a note it
    /// just wrote, so there is no reason to make the user wait on a round
    /// trip to see it in the picker.
    pub fn upsert(&self, note: &Note) {
        self.notes.write().expect("index lock poisoned").insert(
            note.note_id.clone(),
            Entry {
                title: note.title.clone(),
                parent_note_ids: note.parent_note_ids.clone(),
                attributes: note.attributes.clone(),
                child_note_ids: note.child_note_ids.clone(),
            },
        );
        self.persist();
    }

    /// Drop a note from the index -- `rhizome/delete`'s counterpart to
    /// `upsert`, so a deleted note stops appearing in `list`/`children`
    /// without waiting on the next full refresh.
    pub fn remove(&self, note_id: &str) {
        self.notes
            .write()
            .expect("index lock poisoned")
            .remove(note_id);
        self.persist();
    }

    fn persist(&self) {
        let Some(path) = &self.cache_path else {
            return;
        };
        let notes = self.notes.read().expect("index lock poisoned");
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_vec(&*notes) {
            let _ = std::fs::write(path, json);
        }
    }
}

fn load_cache(path: &Path) -> Option<HashMap<String, Entry>> {
    let bytes = std::fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(title: &str, parents: &[&str]) -> Entry {
        Entry {
            title: title.to_string(),
            parent_note_ids: parents.iter().map(|s| s.to_string()).collect(),
            attributes: vec![],
            child_note_ids: vec![],
        }
    }

    fn entry_with_children(title: &str, parents: &[&str], children: &[&str]) -> Entry {
        Entry {
            title: title.to_string(),
            parent_note_ids: parents.iter().map(|s| s.to_string()).collect(),
            attributes: vec![],
            child_note_ids: children.iter().map(|s| s.to_string()).collect(),
        }
    }

    fn entry_with_attrs(title: &str, parents: &[&str], attributes: Vec<Attribute>) -> Entry {
        Entry {
            title: title.to_string(),
            parent_note_ids: parents.iter().map(|s| s.to_string()).collect(),
            attributes,
            child_note_ids: vec![],
        }
    }

    fn attr(attribute_type: &str, name: &str, value: &str) -> Attribute {
        Attribute {
            attribute_id: format!("attr-{name}"),
            note_id: "note".to_string(),
            attribute_type: attribute_type.to_string(),
            name: name.to_string(),
            value: value.to_string(),
            is_inheritable: false,
        }
    }

    fn tree() -> HashMap<String, Entry> {
        let mut notes = HashMap::new();
        notes.insert("work".to_string(), entry("Work", &["root"]));
        notes.insert("projects".to_string(), entry("Projects", &["work"]));
        notes.insert("alpha".to_string(), entry("Alpha", &["projects"]));
        notes
    }

    #[test]
    fn resolve_path_walks_every_ancestor_to_root() {
        assert_eq!(resolve_path(&tree(), "alpha"), vec!["Work", "Projects"]);
    }

    #[test]
    fn resolve_trail_pairs_each_ancestor_with_its_id() {
        assert_eq!(
            resolve_trail(&tree(), "alpha"),
            vec![
                ("work".to_string(), "Work".to_string()),
                ("projects".to_string(), "Projects".to_string()),
            ]
        );
    }

    #[test]
    fn resolve_path_is_empty_for_a_top_level_note() {
        assert_eq!(resolve_path(&tree(), "work"), Vec::<String>::new());
    }

    #[test]
    fn resolve_path_stops_at_a_missing_note() {
        assert_eq!(
            resolve_path(&tree(), "does-not-exist"),
            Vec::<String>::new()
        );
    }

    #[test]
    fn resolve_path_stops_at_a_dangling_parent_reference() {
        let mut notes = tree();
        notes.insert("orphan".to_string(), entry("Orphan", &["missing-parent"]));
        assert_eq!(resolve_path(&notes, "orphan"), Vec::<String>::new());
    }

    #[test]
    fn resolve_path_follows_only_the_first_parent_of_a_clone() {
        let mut notes = tree();
        notes.insert(
            "clone".to_string(),
            entry("Cloned Note", &["projects", "work"]),
        );
        assert_eq!(resolve_path(&notes, "clone"), vec!["Work", "Projects"]);
    }

    #[test]
    fn resolve_path_is_cycle_safe() {
        let mut notes = HashMap::new();
        notes.insert("a".to_string(), entry("A", &["b"]));
        notes.insert("b".to_string(), entry("B", &["a"]));
        // Must terminate rather than looping forever; the exact output for a
        // self-referential tree is not otherwise meaningful.
        let _ = resolve_path(&notes, "a");
    }

    #[test]
    fn list_pairs_every_note_with_its_resolved_path() {
        let mut results = list(&tree());
        results.sort_by(|a, b| a.note_id.cmp(&b.note_id));
        assert_eq!(
            results,
            vec![
                Listed {
                    note_id: "alpha".to_string(),
                    title: "Alpha".to_string(),
                    path: vec!["Work".to_string(), "Projects".to_string()],
                },
                Listed {
                    note_id: "projects".to_string(),
                    title: "Projects".to_string(),
                    path: vec!["Work".to_string()],
                },
                Listed {
                    note_id: "work".to_string(),
                    title: "Work".to_string(),
                    path: vec![],
                },
            ]
        );
    }

    #[test]
    fn listed_resolves_one_note_the_same_way_list_would() {
        assert_eq!(
            listed(&tree(), "alpha"),
            Some(Listed {
                note_id: "alpha".to_string(),
                title: "Alpha".to_string(),
                path: vec!["Work".to_string(), "Projects".to_string()],
            })
        );
    }

    #[test]
    fn listed_is_none_for_a_note_not_in_the_index() {
        assert_eq!(listed(&tree(), "does-not-exist"), None);
    }

    #[test]
    fn children_are_ordered_by_the_parents_own_child_note_ids() {
        let mut notes = HashMap::new();
        notes.insert(
            "work".to_string(),
            entry_with_children("Work", &["root"], &["b", "a", "c"]),
        );
        notes.insert("a".to_string(), entry("A", &["work"]));
        notes.insert("b".to_string(), entry("B", &["work"]));
        notes.insert("c".to_string(), entry("C", &["work"]));

        let ids: Vec<String> = children(&notes, "work")
            .iter()
            .map(|c| c.note_id.clone())
            .collect();
        assert_eq!(ids, vec!["b", "a", "c"]);
    }

    #[test]
    fn children_fall_back_to_title_order_when_child_note_ids_is_empty() {
        let mut notes = HashMap::new();
        notes.insert("work".to_string(), entry("Work", &["root"]));
        notes.insert("charlie".to_string(), entry("Charlie", &["work"]));
        notes.insert("alice".to_string(), entry("Alice", &["work"]));

        let titles: Vec<String> = children(&notes, "work")
            .iter()
            .map(|c| c.title.clone())
            .collect();
        assert_eq!(titles, vec!["Alice", "Charlie"]);
    }

    #[test]
    fn a_cloned_note_appears_under_every_parent_that_lists_it() {
        let mut notes = HashMap::new();
        notes.insert("work".to_string(), entry("Work", &["root"]));
        notes.insert("home".to_string(), entry("Home", &["root"]));
        notes.insert("shared".to_string(), entry("Shared", &["work", "home"]));

        let under_work = children(&notes, "work");
        let under_home = children(&notes, "home");
        assert_eq!(under_work.len(), 1);
        assert_eq!(under_home.len(), 1);
        assert_eq!(under_work[0].note_id, "shared");
        assert_eq!(under_work[0].clone_count, 2);
        assert_eq!(under_home[0].clone_count, 2);
    }

    #[test]
    fn child_count_reflects_a_childs_own_children_not_deeper_descendants() {
        // tree(): work -> projects -> alpha. `projects` has one child of its
        // own (alpha); `alpha` has none.
        let projects = children(&tree(), "work")
            .into_iter()
            .find(|c| c.note_id == "projects")
            .unwrap();
        assert_eq!(projects.child_count, 1);

        let alpha = children(&tree(), "projects")
            .into_iter()
            .find(|c| c.note_id == "alpha")
            .unwrap();
        assert_eq!(alpha.child_count, 0);
    }

    #[test]
    fn children_carry_whether_they_are_archived() {
        let mut notes = HashMap::new();
        notes.insert("work".to_string(), entry("Work", &["root"]));
        notes.insert(
            "old".to_string(),
            entry_with_attrs(
                "Old Project",
                &["work"],
                vec![attr("label", "archived", "")],
            ),
        );
        notes.insert("current".to_string(), entry("Current Project", &["work"]));

        let kids = children(&notes, "work");
        let old = kids.iter().find(|c| c.note_id == "old").unwrap();
        let current = kids.iter().find(|c| c.note_id == "current").unwrap();
        assert!(old.archived);
        assert!(!current.archived);
    }

    #[test]
    fn parents_lists_every_immediate_parent_with_its_title() {
        assert_eq!(
            parents(&tree(), "alpha"),
            vec![("projects".to_string(), "Projects".to_string())]
        );
    }

    #[test]
    fn parents_lists_every_parent_of_a_clone() {
        let mut notes = HashMap::new();
        notes.insert("work".to_string(), entry("Work", &["root"]));
        notes.insert("home".to_string(), entry("Home", &["root"]));
        notes.insert("shared".to_string(), entry("Shared", &["work", "home"]));

        let mut found = parents(&notes, "shared");
        found.sort();
        assert_eq!(
            found,
            vec![
                ("home".to_string(), "Home".to_string()),
                ("work".to_string(), "Work".to_string()),
            ]
        );
    }

    #[test]
    fn parents_is_empty_for_a_note_not_in_the_index() {
        assert_eq!(parents(&tree(), "does-not-exist"), Vec::new());
    }

    #[test]
    fn a_note_added_by_upsert_appears_under_its_parent_before_any_refresh() {
        let index = Index::new(None);
        index.upsert(&Note {
            note_id: "work".to_string(),
            title: "Work".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b1".to_string(),
            is_protected: false,
            parent_note_ids: vec!["root".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        });
        index.upsert(&Note {
            note_id: "new-note".to_string(),
            title: "New Note".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b2".to_string(),
            is_protected: false,
            parent_note_ids: vec!["work".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        });
        // `work`'s own `child_note_ids` was never touched by either upsert
        // (only a full refresh would do that), yet the new note is found by
        // the reverse scan regardless.
        let ids: Vec<String> = index
            .children("work")
            .into_iter()
            .map(|c| c.note_id)
            .collect();
        assert_eq!(ids, vec!["new-note"]);
    }

    #[test]
    fn search_ranks_a_title_match_ahead_of_a_path_only_match() {
        let results = search(&tree(), "proj", 10);
        assert_eq!(results[0].note_id, "projects");
    }

    #[test]
    fn search_finds_a_note_only_by_its_ancestor_path() {
        let results = search(&tree(), "work", 10);
        let ids: Vec<&str> = results.iter().map(|l| l.note_id.as_str()).collect();
        // "work" itself titles-matches; "projects" and "alpha" match only
        // through their ancestor path.
        assert!(ids.contains(&"work"));
        assert!(ids.contains(&"projects"));
        assert!(ids.contains(&"alpha"));
    }

    #[test]
    fn search_is_case_insensitive() {
        assert_eq!(search(&tree(), "ALPHA", 10).len(), 1);
    }

    #[test]
    fn search_returns_nothing_for_an_empty_query() {
        assert!(search(&tree(), "", 10).is_empty());
    }

    #[test]
    fn search_respects_the_limit() {
        assert_eq!(search(&tree(), "a", 1).len(), 1);
    }

    /// Waystone > People > {Alice Smith, John Doe}, Waystone > Places >
    /// Peoria -- a fixture shaped like a real vault with a multi-level path
    /// and sibling notes with unrelated titles, to exercise path-prefix
    /// matching rather than the single-ancestor `tree()` above.
    fn waystone() -> HashMap<String, Entry> {
        let mut notes = HashMap::new();
        notes.insert("waystone".to_string(), entry("Waystone", &["root"]));
        notes.insert("people".to_string(), entry("People", &["waystone"]));
        notes.insert("alice".to_string(), entry("Alice Smith", &["people"]));
        notes.insert("john".to_string(), entry("John Doe", &["people"]));
        notes.insert("places".to_string(), entry("Places", &["waystone"]));
        notes.insert("peoria".to_string(), entry("Peoria", &["places"]));
        notes
    }

    #[test]
    fn search_matches_a_path_typed_without_separators() {
        let results = search(&waystone(), "waystonepeople", 10);
        let ids: Vec<&str> = results.iter().map(|l| l.note_id.as_str()).collect();
        assert!(ids.contains(&"alice"));
        assert!(ids.contains(&"john"));
        assert!(!ids.contains(&"peoria"));
    }

    #[test]
    fn search_matches_abbreviated_path_segments() {
        let results = search(&waystone(), "waypeoplejohn", 10);
        let ids: Vec<&str> = results.iter().map(|l| l.note_id.as_str()).collect();
        assert_eq!(ids, vec!["john"]);
    }

    #[test]
    fn search_matches_a_word_inside_a_multi_word_title() {
        let results = search(&waystone(), "smith", 10);
        let ids: Vec<&str> = results.iter().map(|l| l.note_id.as_str()).collect();
        assert_eq!(ids, vec!["alice"]);
    }

    #[test]
    fn search_treats_a_dash_as_an_optional_separator() {
        let dashed = search(&waystone(), "waystone-people", 10);
        let with_dash: Vec<&str> = dashed.iter().map(|l| l.note_id.as_str()).collect();
        let plain = search(&waystone(), "waystonepeople", 10);
        let without: Vec<&str> = plain.iter().map(|l| l.note_id.as_str()).collect();
        assert_eq!(with_dash, without);
    }

    #[test]
    fn search_ranks_a_folder_above_its_children() {
        let results = search(&waystone(), "waystonepeople", 10);
        assert_eq!(results[0].note_id, "people");
    }

    #[test]
    fn search_ranks_shallower_notes_first() {
        let results = search(&waystone(), "waystone", 10);
        let position = |id: &str| results.iter().position(|l| l.note_id == id).unwrap();
        assert!(position("people") < position("alice"));
        assert!(position("places") < position("peoria"));
    }

    #[test]
    fn search_rejects_scattered_characters() {
        // "alice" happens to be spellable from letters scattered across
        // "Peoria"/"Places", but neither note is actually about Alice --
        // a path-prefix match needs each chunk contiguous in some word, not
        // just present somewhere in the note's path.
        let results = search(&waystone(), "alice", 10);
        let ids: Vec<&str> = results.iter().map(|l| l.note_id.as_str()).collect();
        assert_eq!(ids, vec!["alice"]);
    }

    #[test]
    fn sanitize_host_strips_the_scheme() {
        assert_eq!(
            sanitize_host("https://notes.example.com"),
            "notes.example.com"
        );
        assert_eq!(sanitize_host("http://localhost:8080"), "localhost_8080");
    }

    #[test]
    fn sanitize_host_escapes_everything_but_dots_dashes_and_alphanumerics() {
        assert_eq!(sanitize_host("weird/host:name?x"), "weird_host_name_x");
    }

    #[test]
    fn index_persists_and_reloads_across_instances() {
        let dir = std::env::temp_dir().join(format!("rhizome-index-test-{}", std::process::id()));
        let path = dir.join("cache.json");
        let _ = std::fs::remove_dir_all(&dir);

        let index = Index::new(Some(path.clone()));
        index.replace(vec![Note {
            note_id: "n1".to_string(),
            title: "Hello".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b1".to_string(),
            is_protected: false,
            parent_note_ids: vec!["root".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        }]);

        let reloaded = Index::new(Some(path));
        assert_eq!(reloaded.len(), 1);
        assert_eq!(reloaded.get("n1").unwrap().title, "Hello");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn upsert_adds_or_overwrites_a_single_note() {
        let index = Index::new(None);
        index.upsert(&Note {
            note_id: "n1".to_string(),
            title: "Hello".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b1".to_string(),
            is_protected: false,
            parent_note_ids: vec!["root".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        });
        assert_eq!(index.len(), 1);
        assert_eq!(index.get("n1").unwrap().title, "Hello");

        index.upsert(&Note {
            note_id: "n1".to_string(),
            title: "Renamed".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b2".to_string(),
            is_protected: false,
            parent_note_ids: vec!["root".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        });
        assert_eq!(index.len(), 1);
        assert_eq!(index.get("n1").unwrap().title, "Renamed");
    }

    #[test]
    fn remove_drops_a_note_from_the_index() {
        let index = Index::new(None);
        index.upsert(&Note {
            note_id: "n1".to_string(),
            title: "Hello".to_string(),
            note_type: "text".to_string(),
            mime: "text/html".to_string(),
            blob_id: "b1".to_string(),
            is_protected: false,
            parent_note_ids: vec!["root".to_string()],
            child_note_ids: vec![],
            attributes: vec![],
            date_modified: None,
        });
        assert_eq!(index.len(), 1);
        index.remove("n1");
        assert_eq!(index.len(), 0);
        assert!(index.get("n1").is_none());
    }

    #[test]
    fn definitions_for_reads_a_notes_own_definition() {
        let mut notes = tree();
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![attr("label", "label:status", "promoted,single,text")],
            ),
        );
        let defs = definitions_for(&notes, "alpha");
        let def = defs.get(&(Kind::Label, "status".to_string())).unwrap();
        assert!(def.promoted);
        assert!(!def.multi);
        assert_eq!(def.label_type.as_deref(), Some("text"));
    }

    #[test]
    fn definitions_for_inherits_from_an_ancestor() {
        let mut notes = tree();
        notes.insert(
            "projects".to_string(),
            entry_with_attrs(
                "Projects",
                &["work"],
                vec![attr("label", "label:priority", "promoted,multi,number")],
            ),
        );
        let defs = definitions_for(&notes, "alpha");
        let def = defs.get(&(Kind::Label, "priority".to_string())).unwrap();
        assert!(def.multi);
        assert_eq!(def.label_type.as_deref(), Some("number"));
    }

    #[test]
    fn definitions_for_prefers_the_notes_own_definition_over_an_ancestors() {
        let mut notes = tree();
        notes.insert(
            "projects".to_string(),
            entry_with_attrs(
                "Projects",
                &["work"],
                vec![attr("label", "label:status", "single,text")],
            ),
        );
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![attr("label", "label:status", "multi,number")],
            ),
        );
        let defs = definitions_for(&notes, "alpha");
        let def = defs.get(&(Kind::Label, "status".to_string())).unwrap();
        assert!(def.multi);
        assert_eq!(def.label_type.as_deref(), Some("number"));
    }

    #[test]
    fn definitions_for_understands_relation_definitions() {
        let mut notes = tree();
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![attr("label", "relation:template", "single")],
            ),
        );
        let defs = definitions_for(&notes, "alpha");
        assert!(defs.contains_key(&(Kind::Relation, "template".to_string())));
    }

    #[test]
    fn vocabulary_collects_distinct_names_and_values() {
        let mut notes = tree();
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![
                    attr("label", "genre", "sci-fi"),
                    attr("label", "genre", "cyberpunk"),
                ],
            ),
        );
        notes.insert(
            "projects".to_string(),
            entry_with_attrs(
                "Projects",
                &["work"],
                vec![
                    attr("label", "genre", "sci-fi"),
                    attr("relation", "template", "tpl1"),
                ],
            ),
        );
        let vocab = vocabulary(&notes);
        assert_eq!(vocab.label_names, vec!["genre".to_string()]);
        assert_eq!(vocab.relation_names, vec!["template".to_string()]);
        let mut values = vocab.values[&(Kind::Label, "genre".to_string())].clone();
        values.sort();
        assert_eq!(values, vec!["cyberpunk".to_string(), "sci-fi".to_string()]);
    }

    #[test]
    fn vocabulary_collects_relation_targets_too_for_empty_prefix_suggestions() {
        let mut notes = tree();
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![attr("relation", "isFriendOf", "andre")],
            ),
        );
        notes.insert(
            "projects".to_string(),
            entry_with_attrs(
                "Projects",
                &["work"],
                vec![attr("relation", "isFriendOf", "bea")],
            ),
        );
        let vocab = vocabulary(&notes);
        let mut targets = vocab.values[&(Kind::Relation, "isFriendOf".to_string())].clone();
        targets.sort();
        assert_eq!(targets, vec!["andre".to_string(), "bea".to_string()]);
    }

    #[test]
    fn vocabulary_ignores_system_relations_and_definition_labels() {
        let mut notes = tree();
        notes.insert(
            "alpha".to_string(),
            entry_with_attrs(
                "Alpha",
                &["projects"],
                vec![
                    attr("relation", "internalLink", "other"),
                    attr("label", "label:status", "promoted,single,text"),
                ],
            ),
        );
        let vocab = vocabulary(&notes);
        assert!(vocab.relation_names.is_empty());
        assert!(vocab.label_names.is_empty());
    }
}
