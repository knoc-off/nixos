//! Reconciliation engine.
//!
//! Two pipelines:
//!   * **Stock** (basic/cloze): old parser → Card → stock Anki model
//!   * **Custom** (#model(name)): note_parser → Rhai script → custom marki:* model
//!
//! Identity: `#id(hex)` → `marki::id:<hex>` tag on Anki note.
//! Hash: blake3 over all rendered field values.
//!
//! Policy (destructive):
//!   * disk is authoritative
//!   * Anki notes without a matching `.md` file get `deleteNotes`
//!   * Anki-side edits are silently overwritten

use anyhow::{Context, Result};
use marki_core::EmittedAsset;
use rhai::Dynamic;
use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use crate::anki::client::AnkiConnect;
use crate::anki::model::{ManagedNote, ModelKind, full_tag_set};
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
) -> Result<Outcome> {
    let mut outcome = Outcome::default();

    // ---- Phase 1: Build local index.
    let mut local: HashMap<String, Local> = HashMap::new();
    let mut ensured_models: HashSet<String> = HashSet::new();

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
                    outcome.moved += 1;
                }
            }
            None => {
                if dry_run {
                    outcome.added += 1;
                } else {
                    match push_add(anki, l) {
                        Ok(_) => outcome.added += 1,
                        Err(e) => outcome.errors.push(format!(
                            "{}: add: {e}",
                            l.path.display()
                        )),
                    }
                }
            }
        }
    }

    // ---- Phase 4: Delete orphans.
    let orphan_ids: Vec<i64> = remote
        .values()
        .map(|r| r.anki_note_id)
        .collect();
    if !orphan_ids.is_empty() {
        if dry_run {
            outcome.deleted += orphan_ids.len();
        } else {
            match anki.delete_notes(&orphan_ids) {
                Ok(()) => outcome.deleted += orphan_ids.len(),
                Err(e) => outcome.errors.push(format!("deleteNotes: {e}")),
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
}
