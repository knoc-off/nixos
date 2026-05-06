//! Rhai type registration for Note, Block, and related types.
//!
//! Registers custom types and their methods so Rhai scripts can call
//! `note.paragraphs()`, `note.code_block("map")`, `block.html()`, etc.

use marki_core::note::{Block, Note, TagValue};
use rhai::{Dynamic, Engine, ImmutableString};

use super::context::register_context_types;

/// Register all marki types into the Rhai engine.
pub fn register_types(engine: &mut Engine) {
    // ---- Note ----
    engine.register_type_with_name::<Note>("Note")
        .register_get("id", note_id)
        .register_get("model", note_model)
        .register_get("source", note_source)
        .register_get("anki_tags", note_anki_tags);

    engine.register_fn("sections", note_sections);
    engine.register_fn("section", note_section);
    engine.register_fn("section_html", note_section_html);
    engine.register_fn("paragraphs", note_paragraphs);
    engine.register_fn("paragraph", note_paragraph);
    engine.register_fn("headings", note_headings);
    engine.register_fn("heading", note_heading);
    engine.register_fn("code_blocks", note_code_blocks);
    engine.register_fn("code_block", note_code_block);
    engine.register_fn("lists", note_lists);
    engine.register_fn("blockquotes", note_blockquotes);
    engine.register_fn("tag", note_tag);
    engine.register_fn("has_tag", note_has_tag);
    engine.register_fn("body_html", note_body_html);

    // ---- Block ----
    engine.register_type_with_name::<Block>("Block")
        .register_get("text", block_text)
        .register_get("html", block_html)
        .register_get("lang", block_lang)
        .register_get("source", block_source);

    // ---- TagValue ----
    engine.register_type_with_name::<TagValue>("TagValue");
    engine.register_fn("is_bool", tagvalue_is_bool);
    engine.register_fn("value", tagvalue_value);

    // ---- Context + RenderedBlock ----
    register_context_types(engine);
}

// ---------- Note accessors ----------

fn note_id(note: &mut Note) -> Dynamic {
    match &note.id {
        Some(id) => Dynamic::from(id.clone()),
        None => Dynamic::UNIT,
    }
}

fn note_model(note: &mut Note) -> ImmutableString {
    note.model.clone().into()
}

fn note_source(note: &mut Note) -> ImmutableString {
    note.source.clone().into()
}

fn note_anki_tags(note: &mut Note) -> rhai::Array {
    note.anki_tags.iter().map(|t| Dynamic::from(t.clone())).collect()
}

fn note_sections(note: &mut Note) -> rhai::Array {
    note.sections()
        .into_iter()
        .map(|sec| {
            let arr: rhai::Array = sec.into_iter().cloned().map(Dynamic::from).collect();
            Dynamic::from(arr)
        })
        .collect()
}

fn note_section(note: &mut Note, n: i64) -> rhai::Array {
    note.section(n as usize)
        .into_iter()
        .cloned()
        .map(Dynamic::from)
        .collect()
}

fn note_section_html(note: &mut Note, n: i64) -> ImmutableString {
    note.section_html(n as usize).into()
}

fn note_paragraphs(note: &mut Note) -> rhai::Array {
    note.paragraphs().into_iter().cloned().map(Dynamic::from).collect()
}

fn note_paragraph(note: &mut Note, n: i64) -> Dynamic {
    match note.paragraph(n as usize) {
        Some(b) => Dynamic::from(b.clone()),
        None => Dynamic::UNIT,
    }
}

fn note_headings(note: &mut Note) -> rhai::Array {
    note.headings().into_iter().cloned().map(Dynamic::from).collect()
}

fn note_heading(note: &mut Note, n: i64) -> Dynamic {
    match note.heading(n as usize) {
        Some(b) => Dynamic::from(b.clone()),
        None => Dynamic::UNIT,
    }
}

fn note_code_blocks(note: &mut Note, lang: &str) -> rhai::Array {
    note.code_blocks(lang).into_iter().cloned().map(Dynamic::from).collect()
}

fn note_code_block(note: &mut Note, lang: &str) -> Dynamic {
    match note.code_block(lang) {
        Some(b) => Dynamic::from(b.clone()),
        None => Dynamic::UNIT,
    }
}

fn note_lists(note: &mut Note) -> rhai::Array {
    note.lists().into_iter().cloned().map(Dynamic::from).collect()
}

fn note_blockquotes(note: &mut Note) -> rhai::Array {
    note.blockquotes().into_iter().cloned().map(Dynamic::from).collect()
}

fn note_tag(note: &mut Note, name: &str) -> Dynamic {
    match note.tag(name) {
        Some(tv) => Dynamic::from(tv.clone()),
        None => Dynamic::UNIT,
    }
}

fn note_has_tag(note: &mut Note, name: &str) -> bool {
    note.has_tag(name)
}

fn note_body_html(note: &mut Note) -> ImmutableString {
    note.body_html().into()
}

// ---------- Block accessors ----------

fn block_text(block: &mut Block) -> ImmutableString {
    block.text().to_string().into()
}

fn block_html(block: &mut Block) -> ImmutableString {
    block.html().to_string().into()
}

fn block_lang(block: &mut Block) -> Dynamic {
    match block.lang() {
        Some(l) => Dynamic::from(l.to_string()),
        None => Dynamic::UNIT,
    }
}

fn block_source(block: &mut Block) -> Dynamic {
    match block.source() {
        Some(s) => Dynamic::from(s.to_string()),
        None => Dynamic::UNIT,
    }
}

// ---------- TagValue accessors ----------

fn tagvalue_is_bool(tv: &mut TagValue) -> bool {
    matches!(tv, TagValue::Bool)
}

fn tagvalue_value(tv: &mut TagValue) -> Dynamic {
    match tv {
        TagValue::Bool => Dynamic::from(true),
        TagValue::Param(s) => Dynamic::from(s.clone()),
    }
}
