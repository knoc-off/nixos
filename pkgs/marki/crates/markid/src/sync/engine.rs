//! Destructive reconciliation between disk and Anki.
//!
//! Identity is our `#id(...)` (a minted UUID). The server's role is purely
//! to push — it never writes back to disk. If the formatter (`markid fmt`)
//! hasn't run yet for a file (no `#id`), the daemon skips it with a warning.
//! That keeps this loop pure: scan, diff, push. Nothing more.
//!
//! Policy (destructive):
//!   * disk is authoritative
//!   * Anki notes without a matching `.md` file get `deleteNotes`
//!   * Anki-side edits are silently overwritten

use anyhow::{Context, Result};
use marki_core::card::{Card, NoteType};
use std::collections::{HashMap, HashSet};
use std::path::Path;

use crate::anki::{AnkiConnect, ManagedNote, ModelKind};
use crate::scan::{ScannedCard, deck_for};
use crate::sync::media;

#[derive(Default)]
pub struct Outcome {
    pub added: usize,
    pub updated: usize,
    pub moved: usize,
    pub deleted: usize,
    /// Files that have no `#id(...)` yet — formatter hasn't run. Not an
    /// error but surfaced so operators know the state is incomplete.
    pub unformatted: usize,
    pub errors: Vec<String>,
}

struct Local<'a> {
    sc: &'a ScannedCard,
    card: &'a Card,
    deck: String,
}

pub fn reconcile(
    anki: &AnkiConnect,
    root: &Path,
    scanned: &[ScannedCard],
) -> Result<Outcome> {
    let mut outcome = Outcome::default();

    for sc in scanned {
        for e in &sc.parsed.errors {
            outcome
                .errors
                .push(format!("{}: {e}", sc.path.display()));
        }
    }

    // ---- Build local index keyed by marki_id (String).
    let mut local: HashMap<String, Local<'_>> = HashMap::new();
    for sc in scanned {
        let card = &sc.parsed.card;
        match &card.id {
            Some(id) => {
                let deck = deck_for(root, &sc.path);
                if let Some(prev) = local.insert(
                    id.clone(),
                    Local {
                        sc,
                        card,
                        deck: deck.clone(),
                    },
                ) {
                    outcome.errors.push(format!(
                        "duplicate marki id {id} claimed by {} and {}",
                        prev.sc.path.display(),
                        sc.path.display()
                    ));
                }
            }
            None => {
                outcome.unformatted += 1;
                tracing::warn!(
                    "{} has no #id; run `markid fmt` (or commit from a machine that will)",
                    sc.path.display()
                );
            }
        }
    }

    // ---- Pull remote state (keyed by marki_id).
    let remote_vec = anki
        .managed_notes()
        .context("fetch remote managed notes")?;
    let mut remote: HashMap<String, ManagedNote> = remote_vec
        .into_iter()
        .map(|n| (n.marki_id.clone(), n))
        .collect();

    let local_ids: HashSet<&str> = local.keys().map(|s| s.as_str()).collect();

    for (id, l) in &local {
        match remote.remove(id) {
            Some(r) => {
                let new_hash = &l.card.current_hash;
                let content_diverged = *new_hash != r.hash;
                let deck_diverged = l.deck != r.deck;

                if content_diverged {
                    if let Err(e) = push_update(anki, root, l, &r) {
                        outcome
                            .errors
                            .push(format!("{}: update: {e}", l.sc.path.display()));
                        continue;
                    }
                    if deck_diverged {
                        if let Err(e) = anki.change_deck(&r.card_ids, &l.deck) {
                            outcome.errors.push(format!(
                                "{}: changeDeck: {e}",
                                l.sc.path.display()
                            ));
                            continue;
                        }
                    }
                    outcome.updated += 1;
                } else if deck_diverged {
                    if let Err(e) = anki.change_deck(&r.card_ids, &l.deck) {
                        outcome.errors.push(format!(
                            "{}: changeDeck: {e}",
                            l.sc.path.display()
                        ));
                        continue;
                    }
                    outcome.moved += 1;
                }
            }
            None => match push_add(anki, root, l.sc, l.card, id, &l.deck) {
                Ok(_) => outcome.added += 1,
                Err(e) => outcome
                    .errors
                    .push(format!("{}: add: {e}", l.sc.path.display())),
            },
        }
    }

    // ---- Delete orphans (remote notes with no disk counterpart).
    let orphan_anki_ids: Vec<i64> = remote
        .values()
        .filter(|r| !local_ids.contains(r.marki_id.as_str()))
        .map(|r| r.anki_note_id)
        .collect();
    if !orphan_anki_ids.is_empty() {
        match anki.delete_notes(&orphan_anki_ids) {
            Ok(()) => outcome.deleted += orphan_anki_ids.len(),
            Err(e) => outcome.errors.push(format!("deleteNotes: {e}")),
        }
    }

    Ok(outcome)
}

fn push_add(
    anki: &AnkiConnect,
    root: &Path,
    sc: &ScannedCard,
    card: &Card,
    marki_id: &str,
    deck: &str,
) -> Result<i64> {
    anki.ensure_deck(deck)?;

    let (front_html, back_html) = rewrite_media_refs(anki, root, &sc.path, card)?;
    let model = model_for(card.note_type);
    let fields = visible_fields_for(model, &front_html, &back_html);

    let id = anki.add_note(
        deck,
        model,
        &fields,
        &card.anki_tags,
        marki_id,
        &card.current_hash,
    )?;
    Ok(id)
}

fn push_update(
    anki: &AnkiConnect,
    root: &Path,
    l: &Local<'_>,
    r: &ManagedNote,
) -> Result<()> {
    let (front_html, back_html) = rewrite_media_refs(anki, root, &l.sc.path, l.card)?;
    let model = model_for(l.card.note_type);
    let fields = visible_fields_for(model, &front_html, &back_html);
    anki.update_note_fields(r.anki_note_id, &fields)?;
    anki.update_note_tags(
        r.anki_note_id,
        &l.card.anki_tags,
        &r.marki_id,
        &l.card.current_hash,
    )?;
    Ok(())
}

fn model_for(nt: NoteType) -> ModelKind {
    match nt {
        NoteType::Basic => ModelKind::Basic,
        NoteType::Cloze => ModelKind::Cloze,
    }
}

fn visible_fields_for<'a>(
    model: ModelKind,
    front: &'a str,
    back: &'a str,
) -> Vec<(&'static str, &'a str)> {
    match model {
        ModelKind::Basic => vec![("Front", front), ("Back", back)],
        ModelKind::Cloze => vec![("Text", front), ("Extra", back)],
    }
}

fn rewrite_media_refs(
    anki: &AnkiConnect,
    root: &Path,
    md_file: &Path,
    card: &Card,
) -> Result<(String, String)> {
    let mut front = card.front_html.clone();
    let mut back = card.back_html.clone();

    let mut seen: HashMap<String, String> = HashMap::new();

    for src in &card.media_refs {
        if seen.contains_key(src) {
            continue;
        }
        let Some(resolved) = media::resolve(root, md_file, src) else {
            tracing::warn!(
                "media not found: {} (referenced by {})",
                src,
                md_file.display()
            );
            continue;
        };
        let stored = media::push_media(anki, &resolved)?;
        seen.insert(src.clone(), stored);
    }

    for (src, stored) in &seen {
        let escaped_src = html_escape(src);
        let from = format!("src=\"{escaped_src}\"");
        let to = format!("src=\"{stored}\"");
        front = front.replace(&from, &to);
        back = back.replace(&from, &to);
    }

    Ok((front, back))
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            '"' => out.push_str("&quot;"),
            c => out.push(c),
        }
    }
    out
}
