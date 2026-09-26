//! Reconciliation engine.
//!
//! Every note -- basic or `#model(name)` -- is materialized as a `marki:<name>`
//! notetype in the collection and written directly through `marki-anki`.
//!
//! Identity: `#id(hex)` becomes the note's `guid`. Hash: blake3 over the
//! rendered field values, stored as a `marki::hash:<hex>` tag.
//!
//! Policy:
//!   * disk is authoritative for *content*: collection-side edits are overwritten
//!   * a note is an orphan only when its `#id()` is absent from disk; a card
//!     that exists on disk but fails to render is preserved untouched, never
//!     deleted (see `is_orphan` + `seen_source_ids`)
//!   * orphans are soft-deleted by default (suspend + `marki::orphan` tag),
//!     hard-deleted only with `--prune`
//!   * nothing is pruned at all during a cycle that had render errors

use anyhow::{Context, Result};
use marki_anki::notetype::ModelSpec;
use marki_anki::{Collection, ModelChangeOpts, NoteWriter, RawManagedNote};
use marki_render::Asset;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use crate::anki::model::{MARKER_TAG, ORPHAN_TAG, full_tag_set, hash_from_tags};
use crate::note::Note;
use crate::render::Registry;
use crate::scan::{ScannedNote, deck_for_note};
use crate::scripting::context::RenderContext;
use crate::scripting::engine::ScriptEngine;

/// The single card name a basic note's `marki:basic` notetype uses. Its two
/// fields are `CardFront`/`CardBack`.
const BASIC_CARD_NAME: &str = "Card";

/// Minimal default CSS applied to a notetype with no `<model>.css` on disk.
const DEFAULT_CSS: &str = r#"
.card {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 16px;
    text-align: center;
    color: #1a1a1a;
    background: #fafafa;
    padding: 1em;
}
img {
    max-width: 100%;
    height: auto;
}
"#;

#[derive(Default)]
pub struct Outcome {
    pub added: usize,
    pub updated: usize,
    pub moved: usize,
    pub deleted: usize,
    /// Orphans suspended + tagged `marki::orphan` instead of deleted.
    pub quarantined: usize,
    /// Orphans left untouched because the cycle had errors (safety valve).
    pub skipped_prune: usize,
    pub unformatted: usize,
    pub errors: Vec<String>,
    /// The plan: models first, then notes in path order, orphans last (by
    /// id). Filled for dry runs too, so `status` and simulations can say
    /// *what* changes. Media entries are appended by the caller, which owns
    /// the media store (see `sync::media::plan`).
    pub changes: Vec<Change>,
    /// Every renderer-emitted asset of the rendered notes, deduplicated by
    /// filename. Reconcile never writes them; the caller pushes them to the
    /// media store before the collection.
    pub assets: Vec<Asset>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, strum::IntoStaticStr)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum ChangeKind {
    /// A notetype is created or changed (id = notetype name).
    Model,
    /// A media file is written or registered (id = filename).
    Media,
    Add,
    Update,
    Move,
    ModelChange,
    Orphan,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct Change {
    pub kind: ChangeKind,
    pub id: String,
    /// Source file; `None` for orphans (their file is gone).
    pub path: Option<std::path::PathBuf>,
    /// Human detail: `deck A -> B`, `model X -> Y`, ...
    pub detail: String,
    /// Hash of the rendered fields being written (empty for orphans), so a
    /// plan fingerprint changes when content does.
    pub content_hash: String,
    /// Applying this bumps the collection schema, so every client must do a
    /// one-way full sync afterwards.
    pub full_sync: bool,
}

/// A fully resolved local note ready for diffing against the collection.
struct Local {
    path: std::path::PathBuf,
    guid: String,
    spec: ModelSpec,
    /// Rename/removal permissions declared by the model script.
    change_opts: ModelChangeOpts,
    /// Field values in ord order (`CardFront`, `CardBack`, ...).
    fields: Vec<String>,
    anki_tags: Vec<String>,
    deck: String,
    assets: Vec<Asset>,
    hash: String,
}

impl Local {
    fn model_name(&self) -> String {
        self.spec.notetype_name()
    }
}

/// One planned mutation against the collection, decided in a pure pass so the
/// same diff drives both `--dry-run` counting and the write transaction.
enum Plan<'a> {
    Add(&'a Local),
    /// Notetype changed -- remove the old note and re-add under the new model.
    ModelChange(&'a RawManagedNote, &'a Local),
    /// Content changed; `bool` is whether the deck also changed.
    Update(&'a RawManagedNote, &'a Local, bool),
    /// Only the deck changed.
    Move(&'a RawManagedNote, &'a Local),
}

#[allow(clippy::too_many_arguments)]
pub fn reconcile(
    col: &mut Collection,
    root: &Path,
    notes: &[ScannedNote],
    script_engine: &mut ScriptEngine,
    registry: &Arc<Registry>,
    cache_dir: &Path,
    models_dir: &Path,
    dry_run: bool,
    prune: bool,
) -> Result<Outcome> {
    let mut outcome = Outcome::default();

    // ---- Phase 1: Build the local index.
    let mut local: HashMap<String, Local> = HashMap::new();

    // Every marki id present on disk this cycle, recorded *before* and
    // independent of render success. A card that fails to render is dropped
    // from `local`, but its id stays here so orphan detection never mistakes a
    // render failure for a deletion. This is the core data-loss guard.
    let mut seen_source_ids: HashSet<String> = HashSet::new();

    for sn in notes {
        let note = &sn.note;

        let guid = match &note.id {
            Some(id) => id.clone(),
            None => {
                outcome.unformatted += 1;
                continue;
            }
        };

        // Record the id as present on disk regardless of what happens next.
        seen_source_ids.insert(guid.clone());

        let entry = match render_note(sn, script_engine, registry, cache_dir, models_dir) {
            Ok(r) => {
                for e in &r.errors {
                    outcome.errors.push(format!("{}: {e}", sn.path.display()));
                }
                let hash = compute_hash(&r.fields);
                Local {
                    path: sn.path.clone(),
                    guid: guid.clone(),
                    spec: r.spec,
                    change_opts: r.change_opts,
                    fields: r.fields,
                    anki_tags: note.anki_tags.clone(),
                    deck: deck_for_note(root, note),
                    assets: r.assets,
                    hash,
                }
            }
            Err(e) => {
                outcome.errors.push(format!("{}: {e:#}", sn.path.display()));
                continue;
            }
        };

        if let Some(prev) = local.insert(guid.clone(), entry) {
            outcome.errors.push(format!(
                "duplicate marki id {} claimed by {} and {}",
                guid,
                prev.path.display(),
                sn.path.display()
            ));
        }
    }

    // ---- Phase 2: Pull remote state.
    let remote_vec = col.managed_notes(MARKER_TAG).context("read managed notes")?;
    let remote: HashMap<String, RawManagedNote> = remote_vec
        .into_iter()
        .map(|n| (n.guid.clone(), n))
        .collect();

    // ---- Phase 3: Compute the plan (pure) and the orphan set.
    let mut plan: Vec<Plan> = Vec::new();
    let mut changes: Vec<Change> = Vec::new();
    for (guid, l) in &local {
        let change = |kind: ChangeKind, detail: String| Change {
            full_sync: kind == ChangeKind::ModelChange,
            kind,
            id: guid.clone(),
            path: Some(l.path.clone()),
            detail,
            content_hash: l.hash.clone(),
        };
        match remote.get(guid) {
            Some(r) => {
                let model_changed = l.model_name() != r.model_name;
                let remote_hash = hash_from_tags(&r.tags).unwrap_or_default();
                let content_changed = l.hash != remote_hash;
                let deck_changed = l.deck != r.deck;
                let deck_note = if deck_changed {
                    format!("deck {} -> {}", r.deck, l.deck)
                } else {
                    String::new()
                };

                if model_changed {
                    plan.push(Plan::ModelChange(r, l));
                    outcome.updated += 1;
                    changes.push(change(
                        ChangeKind::ModelChange,
                        format!("model {} -> {} (full sync required)", r.model_name, l.model_name()),
                    ));
                } else if content_changed {
                    plan.push(Plan::Update(r, l, deck_changed));
                    outcome.updated += 1;
                    changes.push(change(ChangeKind::Update, deck_note));
                } else if deck_changed {
                    plan.push(Plan::Move(r, l));
                    outcome.moved += 1;
                    changes.push(change(ChangeKind::Move, deck_note));
                }
            }
            None => {
                plan.push(Plan::Add(l));
                outcome.added += 1;
                changes.push(change(ChangeKind::Add, format!("deck {}", l.deck)));
            }
        }
    }
    changes.sort_by(|a, b| a.path.cmp(&b.path));

    // An orphan is a managed note whose id is absent from disk. We filter by
    // `seen_source_ids`, NOT merely "unmatched": a note whose source file
    // exists but failed to render this cycle keeps its id in
    // `seen_source_ids` and must be preserved.
    let orphans: Vec<&RawManagedNote> = remote
        .values()
        .filter(|r| is_orphan(&r.guid, &seen_source_ids))
        .collect();
    let mut orphan_changes: Vec<Change> = orphans
        .iter()
        .map(|r| Change {
            kind: ChangeKind::Orphan,
            id: r.guid.clone(),
            path: None,
            detail: format!("{} in {}", r.model_name, r.deck),
            content_hash: String::new(),
            full_sync: false,
        })
        .collect();
    orphan_changes.sort_by(|a, b| a.id.cmp(&b.id));
    changes.extend(orphan_changes);

    // One representative note per model, in a stable order.
    let mut models_in_use: Vec<&Local> = Vec::new();
    let mut seen_models: HashSet<String> = HashSet::new();
    let mut by_path: Vec<&Local> = local.values().collect();
    by_path.sort_by(|a, b| a.path.cmp(&b.path));
    for l in by_path {
        if seen_models.insert(l.model_name()) {
            models_in_use.push(l);
        }
    }
    let mut model_changes = Vec::new();
    for l in &models_in_use {
        if let Some(c) = model_change(col, &l.spec)? {
            model_changes.push(c);
        }
    }
    model_changes.extend(changes);
    outcome.changes = model_changes;
    outcome.assets = collect_assets(&local);

    // ---- Phase 4: Report or apply.
    if dry_run {
        account_orphans(&orphans, prune, &mut outcome);
        return Ok(outcome);
    }

    apply(col, &models_in_use, &plan, &orphans, prune, &mut outcome)?;
    Ok(outcome)
}

/// Ensure a notetype exists, caching the resolved id per model per cycle.
fn ensure_model_cached(
    w: &mut NoteWriter,
    cache: &mut HashMap<String, i64>,
    l: &Local,
) -> Result<i64> {
    let name = l.spec.notetype_name();
    if let Some(&mid) = cache.get(&name) {
        return Ok(mid);
    }
    let mid = w.ensure_model_with(&l.spec, &l.change_opts)?;
    cache.insert(name, mid);
    Ok(mid)
}

/// Apply the plan and orphan handling inside a single exclusive transaction.
fn apply(
    col: &mut Collection,
    models_in_use: &[&Local],
    plan: &[Plan],
    orphans: &[&RawManagedNote],
    prune: bool,
    outcome: &mut Outcome,
) -> Result<()> {
    // Read outside the closure -- the safety valve depends on render errors.
    let had_errors = !outcome.errors.is_empty();

    let (deleted, quarantined, skipped_prune, blocked) = col.transact(|w| {
        let mut ensured: HashMap<String, i64> = HashMap::new();

        // Bring every model in use up to date first, even when none of its
        // notes changed: a script that only renames or appends card types
        // leaves note hashes untouched, so the plan alone would miss it.
        // A model that can't be brought up to date (e.g. a refused template
        // removal) only blocks its own notes, not the whole push.
        let mut blocked: HashMap<String, String> = HashMap::new();
        for l in models_in_use {
            if let Err(e) = ensure_model_cached(w, &mut ensured, l) {
                blocked.insert(l.model_name(), format!("{e:#}"));
            }
        }
        let is_blocked = |l: &Local| blocked.contains_key(&l.model_name());

        for p in plan {
            let l = match p {
                Plan::Add(l) | Plan::ModelChange(_, l) | Plan::Update(_, l, _) | Plan::Move(_, l) => *l,
            };
            if is_blocked(l) {
                continue;
            }
            match p {
                Plan::Add(l) => {
                    let mid = ensure_model_cached(w, &mut ensured, l)?;
                    let did = w.deck_id_for(&l.deck)?;
                    let tags = full_tag_set(&l.anki_tags, &l.hash);
                    w.add_note(mid, &l.guid, l.fields.clone(), 0, &tags, did)?;
                    tracing::debug!(path = %l.path.display(), id = %l.guid, "add");
                }
                Plan::ModelChange(r, l) => {
                    let mid = ensure_model_cached(w, &mut ensured, l)?;
                    let did = w.deck_id_for(&l.deck)?;
                    let tags = full_tag_set(&l.anki_tags, &l.hash);
                    let remap = w.change_note_model(
                        r.note_id,
                        mid,
                        l.fields.clone(),
                        0,
                        &tags,
                        did,
                        &l.change_opts.renames,
                    )?;
                    tracing::info!(
                        path = %l.path.display(),
                        from = %r.model_name,
                        to = %l.model_name(),
                        kept = remap.kept,
                        removed = remap.removed,
                        added = remap.added,
                        "note type changed in place (full sync required)"
                    );
                }
                Plan::Update(r, l, deck_changed) => {
                    // Ensure the model in case the script appended a card
                    // (new fields/templates) since the note was last written.
                    ensure_model_cached(w, &mut ensured, l)?;
                    let tags = full_tag_set(&l.anki_tags, &l.hash);
                    w.update_note(r.note_id, l.fields.clone(), 0, &tags)?;
                    if l.spec.cloze {
                        w.sync_cloze_cards(r.note_id)?;
                    }
                    if *deck_changed {
                        let did = w.deck_id_for(&l.deck)?;
                        w.set_note_deck(r.note_id, did)?;
                    }
                    tracing::debug!(path = %l.path.display(), deck_changed, "update");
                }
                Plan::Move(r, l) => {
                    let did = w.deck_id_for(&l.deck)?;
                    w.set_note_deck(r.note_id, did)?;
                    tracing::debug!(path = %l.path.display(), to = %l.deck, "move");
                }
            }
        }

        // Orphans: notes with no matching source file this cycle.
        if orphans.is_empty() {
            return Ok((0usize, 0usize, 0usize, blocked));
        }
        if had_errors || !blocked.is_empty() {
            // Safety valve: a cycle that hit errors may have failed to render
            // live notes; never prune in that state. Re-run once clean.
            tracing::warn!(
                count = orphans.len(),
                "skipping prune of {} orphan(s) because the cycle had errors; \
                 re-run after fixing them",
                orphans.len()
            );
            return Ok((0, 0, orphans.len(), blocked));
        }
        if prune {
            for r in orphans {
                w.remove_note(r.note_id)?;
            }
            tracing::debug!(count = orphans.len(), "deleted orphaned notes");
            Ok((orphans.len(), 0, 0, blocked))
        } else {
            for r in orphans {
                w.suspend_note_cards(r.note_id)?;
                w.add_tag_to_note(r.note_id, ORPHAN_TAG)?;
            }
            tracing::debug!(count = orphans.len(), "quarantined orphaned notes");
            Ok((0, orphans.len(), 0, blocked))
        }
    })?;

    for (model, e) in blocked {
        outcome.errors.push(format!("model {model}: not updated, its notes were skipped: {e}"));
    }
    outcome.deleted = deleted;
    outcome.quarantined = quarantined;
    outcome.skipped_prune = skipped_prune;
    Ok(())
}

/// Count orphan handling for a dry run, applying the same safety valve.
/// What writing `spec` does to the collection's notetype, `None` when it is
/// already up to date. Mirrors `ensure_model_with`'s decision: a new
/// notetype or changed card list bumps the schema (full sync); a css-only
/// change does not.
fn model_change(col: &Collection, spec: &ModelSpec) -> Result<Option<Change>> {
    let name = spec.notetype_name();
    let want = spec.template_names();
    let (detail, full_sync) = match col.notetype_state(&name)? {
        None => (format!("new note type, cards {}", want.join(", ")), true),
        Some((have, _)) if have != want => {
            (format!("cards {} -> {}", have.join(", "), want.join(", ")), true)
        }
        Some((_, css)) if css != spec.css => ("css".to_string(), false),
        Some(_) => return Ok(None),
    };
    let mut h = blake3::Hasher::new();
    h.update(want.join("\0").as_bytes());
    h.update(b"\0");
    h.update(spec.css.as_bytes());
    Ok(Some(Change {
        kind: ChangeKind::Model,
        id: name,
        path: None,
        detail,
        content_hash: h.finalize().to_hex()[..16].to_string(),
        full_sync,
    }))
}

fn account_orphans(orphans: &[&RawManagedNote], prune: bool, outcome: &mut Outcome) {
    if orphans.is_empty() {
        return;
    }
    if !outcome.errors.is_empty() {
        outcome.skipped_prune = orphans.len();
    } else if prune {
        outcome.deleted = orphans.len();
    } else {
        outcome.quarantined = orphans.len();
    }
}

/// Gather every renderer-emitted asset across all locals, deduplicated by
/// filename (renderers content-address their output, so equal names are equal
/// bytes).
fn collect_assets(local: &HashMap<String, Local>) -> Vec<Asset> {
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for l in local.values() {
        for a in &l.assets {
            if seen.insert(a.filename.clone()) {
                out.push(a.clone());
            }
        }
    }
    out
}

/// Load a notetype's CSS from `<models_dir>/<name>.css`, falling back to a
/// minimal default when absent.
fn load_model_css(models_dir: &Path, name: &str) -> String {
    let path = models_dir.join(format!("{name}.css"));
    std::fs::read_to_string(&path).unwrap_or_else(|_| {
        if name == "cloze" {
            format!("{DEFAULT_CSS}{CLOZE_CSS}")
        } else {
            DEFAULT_CSS.to_string()
        }
    })
}

/// Anki styles the active cloze span with `.cloze`; without a rule it is
/// indistinguishable from surrounding text.
const CLOZE_CSS: &str = r#".cloze {
    font-weight: bold;
    color: #1565c0;
}
.nightMode .cloze {
    color: #90caf9;
}
"#;

// ---- Stock pipeline (basic) ----

/// Fields and assets for a stock ("Basic"/"Cloze") note. Kept as named
/// `(field, value)` pairs because the offline preview reads
/// them by name; the reconcile engine takes only the values.
pub struct StockRenderResult {
    /// `("Front", html)`/`("Back", html)` for Basic;
    /// `("Text", html)`/`("Back Extra", html)` for Cloze.
    pub fields: Vec<(String, String)>,
    /// Assets emitted by block renderers (SVGs, etc.).
    pub assets: Vec<Asset>,
    /// Non-fatal errors encountered while rendering.
    pub errors: Vec<String>,
}

/// Render a basic/cloze note into stock card fields, routing every block
/// through the shared [`Registry::render_blocks`] path.
///
/// Section 0 is the front; section 1 (if present) is the back. Any `reveal`
/// extras produced while rendering either section are appended to the back.
pub fn render_stock(
    note: &Note,
    registry: &Registry,
    source_path: &Path,
    cache_dir: &Path,
) -> StockRenderResult {
    let front = registry.render_blocks(note.section(0), source_path, cache_dir);
    let back = registry.render_blocks(note.section(1), source_path, cache_dir);

    let mut errors = front.errors;
    errors.extend(back.errors);

    let mut final_back = back.html;
    for extras in [&front.reveal, &back.reveal] {
        if !extras.is_empty() {
            if !final_back.is_empty() {
                final_back.push('\n');
            }
            final_back.push_str(extras);
        }
    }

    let mut assets = front.assets;
    assets.extend(back.assets);

    let fields = if note.model == "cloze" {
        vec![("Text".into(), front.html), ("Back Extra".into(), final_back)]
    } else {
        vec![("Front".into(), front.html), ("Back".into(), final_back)]
    };

    StockRenderResult { fields, assets, errors }
}

/// A note rendered into its notetype: the spec it needs, field values in
/// ord order, emitted assets and non-fatal render errors. Shared by sync and
/// preview so both see exactly the same HTML.
pub struct RenderedNote {
    pub spec: ModelSpec,
    pub change_opts: ModelChangeOpts,
    pub fields: Vec<String>,
    pub assets: Vec<Asset>,
    pub errors: Vec<String>,
}

impl RenderedNote {
    /// Field value by notetype field name (`CardFront`, `Text`, ...).
    pub fn field(&self, name: &str) -> &str {
        self.spec
            .field_names()
            .iter()
            .position(|n| n == name)
            .and_then(|i| self.fields.get(i))
            .map_or("", String::as_str)
    }
}

/// Render one note. Basic/cloze go through the stock pipeline; anything else
/// runs its model script. A hard failure (missing model, script error, no
/// cards at all) is `Err`; block-level render problems land in `errors`.
pub fn render_note(
    sn: &ScannedNote,
    script_engine: &mut ScriptEngine,
    registry: &Arc<Registry>,
    cache_dir: &Path,
    models_dir: &Path,
) -> Result<RenderedNote> {
    let r = render_note_inner(sn, script_engine, registry, cache_dir, models_dir)?;
    // Anki would store the note with zero cards: invisible and unreviewable.
    if crate::preview::cards(&r).is_empty() {
        anyhow::bail!(if r.spec.cloze {
            "note makes no cards: no cloze deletions (mark answers **bold** or *italic*)".to_string()
        } else {
            format!(
                "note makes no cards: every front is empty ({})",
                r.spec.card_names.iter().map(|c| format!("{c}Front")).collect::<Vec<_>>().join(", ")
            )
        });
    }
    Ok(r)
}

fn render_note_inner(
    sn: &ScannedNote,
    script_engine: &mut ScriptEngine,
    registry: &Arc<Registry>,
    cache_dir: &Path,
    models_dir: &Path,
) -> Result<RenderedNote> {
    let note = &sn.note;
    let css = load_model_css(models_dir, &note.model);

    if note.model == "basic" || note.model == "cloze" {
        let r = render_stock(note, registry.as_ref(), &sn.path, cache_dir);
        let cloze = note.model == "cloze";
        return Ok(RenderedNote {
            spec: ModelSpec {
                name: note.model.clone(),
                css,
                card_names: if cloze { vec![] } else { vec![BASIC_CARD_NAME.to_string()] },
                cloze,
            },
            change_opts: ModelChangeOpts::default(),
            fields: r.fields.into_iter().map(|(_, v)| v).collect(),
            assets: r.assets,
            errors: r.errors,
        });
    }

    let model = script_engine
        .load_model(&note.model)
        .with_context(|| format!("load model '{}'", note.model))?;
    let spec = ModelSpec {
        name: note.model.clone(),
        css,
        card_names: model.card_names.clone(),
        cloze: false,
    };
    let ctx = RenderContext::new(Arc::clone(registry), sn.path.clone(), cache_dir.to_path_buf());
    let output = script_engine
        .execute(&model, note.clone(), ctx.clone())
        .context("script error")?;
    // Field values in ord order; a field the script did not emit is empty,
    // which suppresses that card in Anki.
    let fields = spec
        .field_names()
        .iter()
        .map(|name| output.get(name).cloned().unwrap_or_default())
        .collect();
    Ok(RenderedNote {
        spec,
        change_opts: ModelChangeOpts {
            renames: model.renames.clone(),
            allow_removal: model.allow_card_removal,
        },
        fields,
        assets: ctx.take_assets(),
        errors: Vec::new(),
    })
}

/// Decide whether a managed note is a true orphan: its id is absent from disk
/// this cycle. A note whose source `.md` still exists but merely *failed to
/// render* keeps its id in `seen_source_ids` and is NOT an orphan -- the
/// invariant that stops render errors from deleting studied notes.
fn is_orphan(guid: &str, seen_source_ids: &HashSet<String>) -> bool {
    !seen_source_ids.contains(guid)
}

/// Hash over all field values, in order.
fn compute_hash(fields: &[String]) -> String {
    let mut hasher = blake3::Hasher::new();
    for value in fields {
        hasher.update(value.as_bytes());
        hasher.update(b"\x00");
    }
    let hash = hasher.finalize();
    hash.to_hex()[..16].to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_changes_on_field_value() {
        assert_ne!(
            compute_hash(&["Hello".into()]),
            compute_hash(&["World".into()])
        );
    }

    #[test]
    fn hash_stable_for_same_input() {
        let f = vec!["<p>Q</p>".to_string(), "<p>A</p>".to_string()];
        assert_eq!(compute_hash(&f), compute_hash(&f));
    }

    #[test]
    fn hash_sensitive_to_field_order() {
        assert_ne!(
            compute_hash(&["X".into(), "Y".into()]),
            compute_hash(&["Y".into(), "X".into()])
        );
    }

    #[test]
    fn failed_render_note_is_not_an_orphan() {
        // The whole point of the data-loss fix: a card whose source file
        // exists on disk -- recorded in seen_source_ids -- must NEVER be
        // treated as an orphan, even if it failed to render and so never
        // made it into `local`.
        let mut seen = HashSet::new();
        seen.insert("studied-but-failed-render".to_string());
        seen.insert("rendered-fine".to_string());

        assert!(
            !is_orphan("studied-but-failed-render", &seen),
            "a note still present on disk must be protected from deletion"
        );
        assert!(!is_orphan("rendered-fine", &seen));
        // Only an id that is genuinely gone from disk is an orphan.
        assert!(is_orphan("deleted-off-disk", &seen));
    }

    // ---- Stock rendering ----

    fn stock(src: &str) -> StockRenderResult {
        let note = crate::note_parser::parse_note(src, std::path::PathBuf::from("/tmp/test.md"));
        render_stock(&note, &Registry::new(), Path::new("/tmp/test.md"), Path::new("/tmp"))
    }

    #[test]
    fn basic_front_back() {
        let r = stock("What is 2+2?\n\n---\n\nFour.\n");
        assert_eq!(r.fields[0].0, "Front");
        assert!(r.fields[0].1.contains("2+2"));
        assert_eq!(r.fields[1].0, "Back");
        assert!(r.fields[1].1.contains("Four"));
    }

    #[test]
    fn cloze_field_names() {
        let r = stock("The capital of France is **Paris**.\n\n#cloze\n");
        assert_eq!(r.fields[0].0, "Text");
        assert_eq!(r.fields[1].0, "Back Extra");
    }

    #[test]
    fn code_block_gets_highlighted() {
        let r = stock("Look:\n\n```rust\nfn main() {}\n```\n");
        // Highlighted code carries inline styles, not a plain <pre><code>.
        assert!(r.fields[0].1.contains("style="));
    }

    #[test]
    fn math_block_gets_mathjax() {
        let r = stock("```math\nx^2\n```\n\n---\n\nAnswer\n");
        assert!(r.fields[0].1.contains("\\[x^2"));
    }

    #[test]
    fn no_back_section() {
        let r = stock("Just a question.\n");
        assert_eq!(r.fields[0].0, "Front");
        assert!(r.fields[0].1.contains("question"));
        assert_eq!(r.fields[1].1, "");
    }
}
