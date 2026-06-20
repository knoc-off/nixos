//! Reconciliation engine.
//!
//! Two pipelines:
//!   * **Stock** (basic/cloze): old parser → Card → stock Anki model
//!   * **Custom** (#model(name)): note_parser → Rhai script → custom marki:* model
//!
//! Identity: `#id(hex)` → `marki::id:<hex>` tag on Anki note.
//! Hash: blake3 over all rendered field values.
//!
//! Policy:
//!   * disk is authoritative for *content*: Anki-side edits are overwritten
//!   * a note is an orphan only when its `#id()` is absent from disk; a card
//!     that exists on disk but fails to render is preserved untouched, never
//!     deleted (see `is_orphan` + `seen_source_ids`)
//!   * orphans are soft-deleted by default (suspend + `marki::orphan` tag),
//!     hard-deleted only with `--prune`
//!   * nothing is pruned at all during a cycle that had render errors

use anyhow::{Context, Result};
use marki_core::EmittedAsset;
use rhai::Dynamic;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use crate::anki::client::AnkiConnect;
use crate::anki::model::{ManagedNote, ModelKind, ORPHAN_TAG, full_tag_set};
use crate::anki::note_type::{NoteTypeSpec, build_field_values, ensure_note_type, push_model_styling};
use crate::anki::template_state::TemplateState;
use crate::render::Registry;
use crate::scan::{ScannedNote, deck_for};
use crate::scripting::context::RenderContext;
use crate::scripting::engine::ScriptEngine;
use crate::sync::media;
use crate::sync::stock_render;

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
}

/// How a note gets pushed to Anki.
enum NoteKind {
    /// Stock Anki model (Basic or Cloze). Fields are ("Front","Back") or ("Text","Back Extra").
    Stock {
        model: ModelKind,
        fields: Vec<(String, String)>,
    },
    /// Custom Rhai model (marki:*). Fields are whatever the script produces.
    Custom {
        spec: NoteTypeSpec,
        fields: Vec<(String, String)>,
    },
}

/// A fully resolved local note ready for diffing against Anki.
struct Local {
    path: std::path::PathBuf,
    marki_id: String,
    kind: NoteKind,
    anki_tags: Vec<String>,
    deck: String,
    assets: Vec<EmittedAsset>,
    hash: String,
}

impl Local {
    fn model_name(&self) -> &str {
        match &self.kind {
            NoteKind::Stock { model, .. } => model.model_name(),
            NoteKind::Custom { spec, .. } => spec.anki_model_name(),
        }
    }

    fn fields(&self) -> &[(String, String)] {
        match &self.kind {
            NoteKind::Stock { fields, .. } => fields,
            NoteKind::Custom { fields, .. } => fields,
        }
    }
}

/// Returns true if this model name should use the stock Anki pipeline.
fn is_stock_model(name: &str) -> bool {
    matches!(name, "basic" | "cloze")
}

pub fn reconcile(
    anki: &AnkiConnect,
    root: &Path,
    notes: &[ScannedNote],
    script_engine: &mut ScriptEngine,
    registry: &Arc<Registry>,
    template_state: &mut TemplateState,
    cache_dir: &Path,
    models_dir: &Path,
    dry_run: bool,
    prune: bool,
) -> Result<Outcome> {
    let mut outcome = Outcome::default();

    // ---- Phase 1: Build local index.
    let mut local: HashMap<String, Local> = HashMap::new();
    let mut ensured_models: HashSet<String> = HashSet::new();

    // Every marki id that exists on disk this cycle, recorded *before* and
    // independent of render success. A card that fails to render is dropped
    // from `local`, but its id stays here so Phase 4 never mistakes a render
    // failure for a deletion. This is the core data-loss guard.
    let mut seen_source_ids: HashSet<String> = HashSet::new();

    for sn in notes {
        let note = &sn.note;

        // Skip notes without an id.
        let marki_id = match &note.id {
            Some(id) => id.clone(),
            None => {
                outcome.unformatted += 1;
                continue;
            }
        };

        // Record the id as present on disk regardless of what happens next.
        seen_source_ids.insert(marki_id.clone());

        let result = if is_stock_model(&note.model) {
            build_stock_local(sn, &marki_id, root, registry, cache_dir, &mut outcome)
        } else {
            build_custom_local(
                sn, &marki_id, root, script_engine, registry,
                template_state, &mut ensured_models, anki, cache_dir, models_dir,
                &mut outcome,
            )
        };

        let entry = match result {
            Some(e) => e,
            None => continue, // error already pushed to outcome
        };

        // Check for duplicate ids.
        if let Some(prev) = local.insert(marki_id.clone(), entry) {
            outcome.errors.push(format!(
                "duplicate marki id {} claimed by {} and {}",
                marki_id,
                prev.path.display(),
                sn.path.display()
            ));
        }
    }

    // ---- Phase 2: Pull remote state.
    let remote_vec = anki
        .managed_notes()
        .context("fetch remote managed notes")?;
    let mut remote: HashMap<String, ManagedNote> = remote_vec
        .into_iter()
        .map(|n| (n.marki_id.clone(), n))
        .collect();

    // ---- Phase 3: Diff and push.
    for (id, l) in &local {
        if !dry_run {
            // Push renderer assets first.
            for asset in &l.assets {
                if let Err(e) = media::push_emitted(anki, asset) {
                    outcome.errors.push(format!(
                        "{}: storeMediaFile: {e}",
                        l.path.display()
                    ));
                }
            }
        }

        match remote.remove(id) {
            Some(r) => {
                let model_changed = l.model_name() != r.model_name;
                let content_changed = l.hash != r.hash;
                let deck_changed = l.deck != r.deck;

                if model_changed {
                    if dry_run {
                        outcome.updated += 1;
                        continue;
                    }
                    // Model type changed (e.g., Basic → Cloze, or Basic → custom).
                    // Can't update in place — delete and re-add.
                    if let Err(e) = anki.delete_notes(&[r.anki_note_id]) {
                        outcome.errors.push(format!(
                            "{}: delete for model change: {e}",
                            l.path.display()
                        ));
                        continue;
                    }
                    match push_add(anki, l) {
                        Ok(_) => {
                            tracing::info!(
                                path = %l.path.display(),
                                from = %r.model_name,
                                to = %l.model_name(),
                                "note type changed — deleted and re-added"
                            );
                            outcome.updated += 1;
                        }
                        Err(e) => outcome.errors.push(format!(
                            "{}: re-add after model change: {e}",
                            l.path.display()
                        )),
                    }
                } else if content_changed {
                    if !dry_run {
                        if let Err(e) = push_update(anki, l, &r) {
                            outcome.errors.push(format!(
                                "{}: update: {e}",
                                l.path.display()
                            ));
                            continue;
                        }
                        if deck_changed {
                            if let Err(e) = anki.change_deck(&r.card_ids, &l.deck) {
                                outcome.errors.push(format!(
                                    "{}: changeDeck: {e}",
                                    l.path.display()
                                ));
                            }
                        }
                    }
                    tracing::debug!(path = %l.path.display(), deck_changed, "update");
                    outcome.updated += 1;
                } else if deck_changed {
                    if !dry_run {
                        if let Err(e) = anki.change_deck(&r.card_ids, &l.deck) {
                            outcome.errors.push(format!(
                                "{}: changeDeck: {e}",
                                l.path.display()
                            ));
                            continue;
                        }
                    }
                    tracing::debug!(path = %l.path.display(), to = %l.deck, "move (deck change)");
                    outcome.moved += 1;
                }
            }
            None => {
                if dry_run {
                    outcome.added += 1;
                } else {
                    match push_add(anki, l) {
                        Ok(_) => {
                            tracing::debug!(path = %l.path.display(), id = %id, "add");
                            outcome.added += 1;
                        }
                        Err(e) => outcome.errors.push(format!(
                            "{}: add: {e}",
                            l.path.display()
                        )),
                    }
                }
            }
        }
    }

    // ---- Phase 4: Handle orphans (Anki notes with no matching .md).
    //
    // An orphan is a managed note whose id is absent from disk. Critically
    // we filter by `seen_source_ids`, NOT merely "leftover in `remote`":
    // a note whose source file exists but failed to render this cycle is
    // still in `remote` (it was never matched into `local`), yet it must be
    // preserved. Only ids that are genuinely gone from disk are orphans.
    let orphans: Vec<&ManagedNote> = remote
        .values()
        .filter(|r| is_orphan(&r.marki_id, &seen_source_ids))
        .collect();

    if !orphans.is_empty() {
        let note_ids: Vec<i64> = orphans.iter().map(|r| r.anki_note_id).collect();

        if !outcome.errors.is_empty() {
            // Safety valve: a cycle that hit errors may have failed to render
            // live notes; never prune in that state. Re-run once clean.
            tracing::warn!(
                count = note_ids.len(),
                errors = outcome.errors.len(),
                "skipping prune of {} orphan(s) because the cycle had {} error(s); \
                 re-run after fixing the errors",
                note_ids.len(),
                outcome.errors.len()
            );
            outcome.skipped_prune = note_ids.len();
        } else if dry_run {
            // Report intent without touching Anki.
            if prune {
                outcome.deleted = note_ids.len();
            } else {
                outcome.quarantined = note_ids.len();
            }
        } else if prune {
            // Explicit hard delete (`--prune`). Irreversible.
            tracing::debug!(count = note_ids.len(), "deleting orphaned notes");
            match anki.delete_notes(&note_ids) {
                Ok(()) => outcome.deleted = note_ids.len(),
                Err(e) => outcome.errors.push(format!("deleteNotes: {e}")),
            }
        } else {
            // Default: soft-delete. Suspend the cards and tag the notes so
            // they leave review but keep all scheduling history, recoverable
            // via `markid prune` or by restoring the source file.
            let card_ids: Vec<i64> =
                orphans.iter().flat_map(|r| r.card_ids.clone()).collect();
            tracing::debug!(
                notes = note_ids.len(),
                cards = card_ids.len(),
                "quarantining orphaned notes (suspend + tag)"
            );
            let mut ok = true;
            if let Err(e) = anki.add_tags(&note_ids, ORPHAN_TAG) {
                outcome.errors.push(format!("addTags {ORPHAN_TAG}: {e}"));
                ok = false;
            }
            if let Err(e) = anki.suspend(&card_ids) {
                outcome.errors.push(format!("suspend: {e}"));
                ok = false;
            }
            if ok {
                outcome.quarantined = note_ids.len();
            }
        }
    }

    Ok(outcome)
}

// ---- Stock pipeline (basic/cloze) ----

/// Build a Local for a basic or cloze note using the unified stock renderer.
fn build_stock_local(
    sn: &ScannedNote,
    marki_id: &str,
    root: &Path,
    registry: &Arc<Registry>,
    cache_dir: &Path,
    outcome: &mut Outcome,
) -> Option<Local> {
    let result = stock_render::render_stock(
        &sn.note,
        registry.as_ref(),
        &sn.path,
        cache_dir,
    );

    for e in &result.errors {
        outcome.errors.push(format!("{}: {e}", sn.path.display()));
    }

    let model = if sn.note.model == "cloze" {
        ModelKind::Cloze
    } else {
        ModelKind::Basic
    };

    let hash = compute_hash(&result.fields);
    let deck = deck_for(root, &sn.path);

    Some(Local {
        path: sn.path.clone(),
        marki_id: marki_id.to_string(),
        kind: NoteKind::Stock { model, fields: result.fields },
        anki_tags: sn.note.anki_tags.clone(),
        deck,
        assets: result.assets,
        hash,
    })
}

// ---- Custom Rhai pipeline ----

/// Build a Local for a custom model note using the Rhai pipeline.
#[allow(clippy::too_many_arguments)]
fn build_custom_local(
    sn: &ScannedNote,
    marki_id: &str,
    root: &Path,
    script_engine: &mut ScriptEngine,
    registry: &Arc<Registry>,
    template_state: &mut TemplateState,
    ensured_models: &mut HashSet<String>,
    anki: &AnkiConnect,
    cache_dir: &Path,
    models_dir: &Path,
    outcome: &mut Outcome,
) -> Option<Local> {
    let note = &sn.note;

    // Load the model script.
    let model = match script_engine.load_model(&note.model) {
        Ok(m) => m,
        Err(e) => {
            outcome.errors.push(format!(
                "{}: load model '{}': {e}",
                sn.path.display(),
                note.model
            ));
            return None;
        }
    };

    // Validate template ordering (append-only).
    if let Err(e) = template_state.validate_and_update(&note.model, &model.card_names) {
        outcome.errors.push(format!(
            "{}: template ordering: {e}",
            sn.path.display()
        ));
        return None;
    }

    // Build note type spec.
    let spec = NoteTypeSpec::new(&note.model, model.card_names.clone());

    // Ensure the note type exists in Anki (once per model per cycle).
    if !ensured_models.contains(&spec.model_name) {
        if let Err(e) = ensure_note_type(anki, &spec) {
            outcome.errors.push(format!(
                "ensure note type '{}': {e}",
                spec.model_name
            ));
            return None;
        }
        if let Err(e) = push_model_styling(anki, &spec, models_dir) {
            tracing::warn!("push styling for '{}': {e}", spec.model_name);
        }
        ensured_models.insert(spec.model_name.clone());
    }

    // Execute the model script.
    let ctx = RenderContext::new(
        Arc::clone(registry),
        sn.path.clone(),
        cache_dir.to_path_buf(),
    );
    let model_output = match script_engine.execute(
        &model,
        Dynamic::from(note.clone()),
        Dynamic::from(ctx.clone()),
    ) {
        Ok(o) => o,
        Err(e) => {
            outcome.errors.push(format!(
                "{}: script error: {e}",
                sn.path.display()
            ));
            return None;
        }
    };

    let assets = ctx.take_assets();
    let fields = build_field_values(&spec, &model_output);
    let hash = compute_hash(&fields);
    let deck = deck_for(root, &sn.path);

    Some(Local {
        path: sn.path.clone(),
        marki_id: marki_id.to_string(),
        kind: NoteKind::Custom { spec, fields },
        anki_tags: note.anki_tags.clone(),
        deck,
        assets,
        hash,
    })
}

// ---- Push helpers ----

fn push_add(anki: &AnkiConnect, l: &Local) -> Result<i64> {
    anki.ensure_deck(&l.deck)?;
    let tags = full_tag_set(&l.anki_tags, &l.marki_id, &l.hash);
    let id = anki.add_note_dynamic(
        &l.deck,
        l.model_name(),
        l.fields(),
        &tags,
    )?;
    Ok(id)
}

fn push_update(anki: &AnkiConnect, l: &Local, r: &ManagedNote) -> Result<()> {
    anki.update_note_fields_dynamic(r.anki_note_id, l.fields())?;
    anki.update_note_tags(
        r.anki_note_id,
        &l.anki_tags,
        &l.marki_id,
        &l.hash,
    )?;
    Ok(())
}

/// Decide whether an Anki-side managed note is a true orphan: its id is
/// absent from disk this cycle. A note whose source `.md` still exists but
/// merely *failed to render* keeps its id in `seen_source_ids` and is NOT
/// an orphan -- this is the invariant that prevents render errors from
/// deleting studied notes.
fn is_orphan(marki_id: &str, seen_source_ids: &HashSet<String>) -> bool {
    !seen_source_ids.contains(marki_id)
}

/// Hash over all field values.
fn compute_hash(fields: &[(String, String)]) -> String {
    let mut hasher = blake3::Hasher::new();
    for (name, value) in fields {
        hasher.update(name.as_bytes());
        hasher.update(b"\x00");
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
        let f1 = vec![("Front".into(), "Hello".into())];
        let f2 = vec![("Front".into(), "World".into())];
        assert_ne!(compute_hash(&f1), compute_hash(&f2));
    }

    #[test]
    fn hash_stable_for_same_input() {
        let f = vec![
            ("Front".into(), "<p>Q</p>".into()),
            ("Back".into(), "<p>A</p>".into()),
        ];
        assert_eq!(compute_hash(&f), compute_hash(&f));
    }

    #[test]
    fn hash_sensitive_to_field_name() {
        let f1 = vec![("Front".into(), "X".into())];
        let f2 = vec![("Back".into(), "X".into())];
        assert_ne!(compute_hash(&f1), compute_hash(&f2));
    }

    #[test]
    fn stock_model_detection() {
        assert!(is_stock_model("basic"));
        assert!(is_stock_model("cloze"));
        assert!(!is_stock_model("geographic-location"));
        assert!(!is_stock_model("custom"));
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
}
