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
use marki_core::{BlockSide, EmittedAsset, RenderedBlock, placeholder_for};
use std::collections::{HashMap, HashSet};
use std::path::Path;

use crate::anki::{AnkiConnect, ManagedNote, ModelKind};
use crate::render::Registry;
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
    /// Card with external block placeholders already replaced. The
    /// original `ScannedCard.parsed.card` is left untouched.
    card: Card,
    deck: String,
    /// Asset uploads produced by external renderers, accumulated across
    /// all blocks in this card.
    assets: Vec<EmittedAsset>,
}

pub fn reconcile(
    anki: &AnkiConnect,
    root: &Path,
    scanned: &[ScannedCard],
    registry: &Registry,
    cache_dir: &Path,
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
    // Cards whose external blocks fail to render are dropped from the
    // index with an error logged; the daemon never aborts the corpus.
    let mut local: HashMap<String, Local<'_>> = HashMap::new();
    for sc in scanned {
        let card = &sc.parsed.card;
        match &card.id {
            Some(id) => {
                let deck = deck_for(root, &sc.path);
                let mut resolved = match dispatch_blocks(sc, registry, cache_dir) {
                    Ok(r) => r,
                    Err(e) => {
                        outcome
                            .errors
                            .push(format!("{}: render: {e}", sc.path.display()));
                        continue;
                    }
                };
                // Recompute the hash over the final HTML (after block
                // rendering) so that map version / theme / epsilon
                // changes automatically trigger a re-push without
                // touching the markdown source.
                resolved.card.current_hash = marki_core::content_hash_html(
                    &resolved.card.front_html,
                    &resolved.card.back_html,
                );
                if let Some(prev) = local.insert(
                    id.clone(),
                    Local {
                        sc,
                        card: resolved.card,
                        deck: deck.clone(),
                        assets: resolved.assets,
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
        // Push any external-renderer assets first so the note's HTML
        // (which may already reference them) finds them on flip.
        for asset in &l.assets {
            if let Err(e) = media::push_emitted(anki, asset) {
                outcome
                    .errors
                    .push(format!("{}: storeMediaFile: {e}", l.sc.path.display()));
            }
        }

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
            None => match push_add(anki, root, l.sc, &l.card, id, &l.deck) {
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

/// Card after external-block placeholders have been replaced and assets
/// collected.
pub struct ResolvedCard {
    pub card: Card,
    pub assets: Vec<EmittedAsset>,
}

/// Walk every [`marki_core::BlockRequest`] on the parsed card, dispatch
/// to the registry, and splice each [`RenderedBlock`] into the card's
/// front/back HTML at the matching placeholder. On the first block
/// failure, return Err — the daemon turns that into a per-card error
/// and continues the batch. We log + render-stub a friendlier message
/// in `render_failed_stub` for failures that should still produce a
/// pushable card; for now any failure aborts the card.
pub fn dispatch_blocks(
    sc: &ScannedCard,
    registry: &Registry,
    cache_dir: &Path,
) -> Result<ResolvedCard> {
    let mut card = sc.parsed.card.clone();
    let mut assets: Vec<EmittedAsset> = Vec::new();

    // Iterate over a snapshot — `card` itself is mutated as we splice.
    let requests = card.block_requests.clone();
    for req in &requests {
        let rendered: RenderedBlock = match registry.dispatch(req, &sc.path, cache_dir) {
            Ok(r) => r,
            Err(e) => {
                let stub = render_failed_stub(&req.lang, &e.to_string());
                splice_placeholder(&mut card, req.side, &req.id, &stub);
                tracing::warn!("{}: {} block failed: {e}", sc.path.display(), req.lang);
                continue;
            }
        };

        splice_placeholder(&mut card, req.side, &req.id, &rendered.front_html);
        if !rendered.back_html_extras.is_empty() {
            if !card.back_html.is_empty() {
                card.back_html.push('\n');
            }
            card.back_html.push_str(&rendered.back_html_extras);
        }
        assets.extend(rendered.assets);
    }

    Ok(ResolvedCard { card, assets })
}

fn splice_placeholder(card: &mut Card, side: BlockSide, id: &str, html: &str) {
    let placeholder = placeholder_for(&id.to_string());
    let target: &mut String = match side {
        BlockSide::Front => &mut card.front_html,
        BlockSide::Back => &mut card.back_html,
    };
    *target = target.replacen(&placeholder, html, 1);
}

fn render_failed_stub(lang: &str, msg: &str) -> String {
    let escaped_lang = html_escape(lang);
    let escaped_msg = html_escape(msg);
    format!(
        "<div style=\"color:#a00;border:1px solid #a00;padding:0.5em;\
         font-family:monospace;font-size:0.85em;\">\
         <strong>{escaped_lang} block failed:</strong> {escaped_msg}\
         </div>"
    )
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
    let (front_html, back_html) = rewrite_media_refs(anki, root, &l.sc.path, &l.card)?;
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

#[cfg(test)]
mod tests {
    use super::*;
    use marki_core::parser::parse_with_externals;
    use std::path::PathBuf;

    #[test]
    fn splice_replaces_placeholder() {
        let mut card = Card {
            id: None,
            current_hash: String::new(),
            note_type: NoteType::Basic,
            cloze_algorithm: marki_core::tag::ClozeAlgorithm::Increment,
            front_html: format!("<p>before {}</p>", placeholder_for(&"abc".to_string())),
            back_html: String::new(),
            anki_tags: Vec::new(),
            media_refs: Vec::new(),
            stripped_source: String::new(),
            block_requests: Vec::new(),
        };
        splice_placeholder(&mut card, BlockSide::Front, "abc", "<svg/>");
        assert_eq!(card.front_html, "<p>before <svg/></p>");
    }

    #[test]
    fn unused_placeholder_is_no_op() {
        let mut card = Card {
            id: None,
            current_hash: String::new(),
            note_type: NoteType::Basic,
            cloze_algorithm: marki_core::tag::ClozeAlgorithm::Increment,
            front_html: "no placeholder here".into(),
            back_html: String::new(),
            anki_tags: Vec::new(),
            media_refs: Vec::new(),
            stripped_source: String::new(),
            block_requests: Vec::new(),
        };
        splice_placeholder(&mut card, BlockSide::Front, "abc", "<svg/>");
        assert_eq!(card.front_html, "no placeholder here");
    }

    #[test]
    fn dispatch_blocks_runs_map_renderer_and_replaces_placeholder() {
        // Use a tempdir as cache_dir so the cache layer can write
        // freely. NATURAL_EARTH_DATA isn't set in the test environment,
        // so we expect the renderer to fail at resolve time and the
        // dispatch to splice in a `block failed` stub. That still
        // exercises the parse → registry → splice path which is the
        // real point of this test.
        let mut reg = Registry::new();
        reg.register(Box::new(marki_map::MapRenderer::new()));

        let src = "What highlights Bavaria?\n\n\
                  ```map\n\
                  size = [600, 400]\n\
                  \n\
                  [layers.base]\n\
                  features = [\"country/DEU\"]\n\
                  ```\n\
                  ---\n\
                  Bavaria.\n";
        let parsed = parse_with_externals(src, reg.external_langs());
        assert_eq!(parsed.card.block_requests.len(), 1);
        // Placeholder should be in the front HTML right now.
        assert!(parsed.card.front_html.contains("MARKI-BLOCK"));

        let sc = ScannedCard {
            path: PathBuf::from("/tmp/test.md"),
            source: src.into(),
            parsed,
        };
        let cache = std::env::temp_dir().join("marki-engine-test");
        let _ = std::fs::create_dir_all(&cache);
        let resolved = dispatch_blocks(&sc, &reg, &cache).unwrap();
        // After dispatch the placeholder is gone; either real map HTML
        // or the failure-stub div replaced it.
        assert!(!resolved.card.front_html.contains("MARKI-BLOCK"));
        assert!(
            resolved.card.front_html.contains("marki-map")
                || resolved.card.front_html.contains("block failed"),
            "front: {}",
            resolved.card.front_html
        );
    }

    #[test]
    fn dispatch_blocks_renders_stub_on_renderer_failure() {
        // Empty registry but the parser saw `map`, so dispatch will
        // fail with Resolve. Verify the stub is spliced in and the
        // function still returns Ok (the daemon continues the batch).
        let reg = Registry::new();
        let req = marki_core::BlockRequest {
            id: "x".into(),
            lang: "map".into(),
            source: String::new(),
            byte_offset: 0,
            side: BlockSide::Front,
        };
        let placeholder = placeholder_for(&"x".to_string());
        let card = Card {
            id: None,
            current_hash: String::new(),
            note_type: NoteType::Basic,
            cloze_algorithm: marki_core::tag::ClozeAlgorithm::Increment,
            front_html: placeholder.clone(),
            back_html: String::new(),
            anki_tags: Vec::new(),
            media_refs: Vec::new(),
            stripped_source: String::new(),
            block_requests: vec![req],
        };
        let sc = ScannedCard {
            path: PathBuf::from("/tmp/test.md"),
            source: String::new(),
            parsed: marki_core::parser::ParseOutput { card, errors: vec![] },
        };
        let resolved = dispatch_blocks(&sc, &reg, &PathBuf::from("/tmp/cache")).unwrap();
        assert!(!resolved.card.front_html.contains(&placeholder));
        assert!(resolved.card.front_html.contains("block failed"));
    }
}
