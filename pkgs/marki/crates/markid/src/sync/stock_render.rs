//! Stock rendering: Note → stock Anki card fields.
//!
//! Renders a `Note` (from the structural parser) into field values for
//! Anki's stock "Basic" or "Cloze" note types. Handles:
//!
//!   * Syntax highlighting for regular code blocks
//!   * External block dispatch (map/media/typst) through the registry
//!   * Math/LaTeX blocks → MathJax wrapper
//!
//! This replaces the old parser's inline rendering + placeholder splicing
//! approach with a single-pass render over the Note's block structure.

use marki_core::note::{Block, Note};
use marki_core::{BlockRequest, BlockSide, EmittedAsset};
use marki_core::highlighter::highlight_code;
use marki_core::util::escape_html;
use std::path::Path;

use crate::render::Registry;

/// Result of rendering a stock card.
pub struct StockRenderResult {
    /// ("Front", html), ("Back", html) for Basic;
    /// ("Text", html), ("Back Extra", html) for Cloze.
    pub fields: Vec<(String, String)>,
    /// Assets emitted by block renderers (SVGs, etc.)
    pub assets: Vec<EmittedAsset>,
    /// Non-fatal errors encountered during rendering.
    pub errors: Vec<String>,
}

/// Render a Note into stock Anki card fields.
///
/// The Note's model must be "basic" or "cloze". Code blocks whose lang
/// matches a registered renderer are dispatched through the registry;
/// others get syntax-highlighted.
pub fn render_stock(
    note: &Note,
    registry: &Registry,
    source_path: &Path,
    cache_dir: &Path,
) -> StockRenderResult {
    let sections = note.sections();
    let mut errors = Vec::new();

    let (front_html, front_extras, front_assets) = render_section(
        sections.first().map(|s| s.as_slice()).unwrap_or(&[]),
        registry,
        source_path,
        cache_dir,
        &mut errors,
    );

    let (back_html, back_extras, back_assets) = if sections.len() > 1 {
        render_section(
            sections[1].as_slice(),
            registry,
            source_path,
            cache_dir,
            &mut errors,
        )
    } else {
        (String::new(), String::new(), Vec::new())
    };

    // Append back_html_extras from both sections to the back.
    let mut final_back = back_html;
    for extras in [&front_extras, &back_extras] {
        if !extras.is_empty() {
            if !final_back.is_empty() {
                final_back.push('\n');
            }
            final_back.push_str(extras);
        }
    }

    let mut assets = front_assets;
    assets.extend(back_assets);

    let is_cloze = note.model == "cloze";

    let fields = if is_cloze {
        vec![
            ("Text".into(), front_html),
            ("Back Extra".into(), final_back),
        ]
    } else {
        vec![
            ("Front".into(), front_html),
            ("Back".into(), final_back),
        ]
    };

    StockRenderResult { fields, assets, errors }
}

/// Render a single section's blocks into HTML.
///
/// Returns (section_html, back_html_extras, assets).
fn render_section(
    blocks: &[&Block],
    registry: &Registry,
    source_path: &Path,
    cache_dir: &Path,
    errors: &mut Vec<String>,
) -> (String, String, Vec<EmittedAsset>) {
    let mut html = String::new();
    let mut back_extras = String::new();
    let mut assets = Vec::new();
    let mut block_index = 0usize;

    for block in blocks {
        match block {
            Block::CodeBlock { lang: Some(lang), source } => {
                if is_external_lang(lang, registry) {
                    // Dispatch through block renderer.
                    let req = BlockRequest {
                        id: format!("stock-{block_index}"),
                        lang: lang.clone(),
                        source: source.clone(),
                        byte_offset: 0,
                        side: BlockSide::Front,
                    };
                    match registry.dispatch(&req, source_path, cache_dir) {
                        Ok(rb) => {
                            html.push_str(&rb.front_html);
                            if !rb.back_html_extras.is_empty() {
                                if !back_extras.is_empty() {
                                    back_extras.push('\n');
                                }
                                back_extras.push_str(&rb.back_html_extras);
                            }
                            assets.extend(rb.assets);
                        }
                        Err(e) => {
                            errors.push(format!("{lang} block: {e}"));
                            html.push_str(&format!(
                                "<div style=\"color:#a00;border:1px solid #a00;\
                                 padding:0.5em;font-family:monospace;font-size:0.85em;\">\
                                 <strong>{lang} block failed:</strong> {}</div>",
                                escape_html(&e.to_string())
                            ));
                        }
                    }
                } else if lang == "math" || lang == "latex" {
                    // MathJax display math.
                    html.push_str("\\[");
                    html.push_str(source);
                    html.push_str("\\]");
                } else {
                    // Syntax-highlighted code block.
                    let effective_lang = lang.strip_prefix('_').unwrap_or(lang);
                    html.push_str(&highlight_code(source, effective_lang));
                }
                block_index += 1;
            }
            Block::CodeBlock { lang: None, source } => {
                html.push_str(&highlight_code(source, "txt"));
                block_index += 1;
            }
            Block::ThematicBreak => {
                // Section boundaries are handled by the caller; skip
                // any stray breaks within a section.
            }
            _ => {
                html.push_str(&block_to_html(block));
            }
        }
    }

    (html, back_extras, assets)
}

/// Check if a lang token is handled by the block renderer registry.
fn is_external_lang(lang: &str, registry: &Registry) -> bool {
    registry.external_langs().contains(&lang)
}

/// Render a non-code block to HTML. Matches note.rs::block_html but
/// is kept here so we don't depend on marki-core internal functions.
fn block_to_html(block: &Block) -> String {
    match block {
        Block::Heading { html, level, .. } => format!("<h{level}>{html}</h{level}>"),
        Block::Paragraph { html, .. } => format!("<p>{html}</p>"),
        Block::List { html, .. } => html.clone(),
        Block::Blockquote { html, .. } => format!("<blockquote>{html}</blockquote>"),
        Block::Table { html } => html.clone(),
        Block::CodeBlock { .. } | Block::ThematicBreak => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use marki_core::note_parser::parse_note;
    use std::path::PathBuf;

    fn empty_registry() -> Registry {
        Registry::new()
    }

    #[test]
    fn basic_front_back() {
        let note = parse_note(
            "What is 2+2?\n\n---\n\nFour.\n",
            PathBuf::from("/tmp/test.md"),
        );
        let reg = empty_registry();
        let result = render_stock(&note, &reg, Path::new("/tmp/test.md"), Path::new("/tmp"));
        assert_eq!(result.fields[0].0, "Front");
        assert!(result.fields[0].1.contains("2+2"));
        assert_eq!(result.fields[1].0, "Back");
        assert!(result.fields[1].1.contains("Four"));
    }

    #[test]
    fn cloze_field_names() {
        let note = parse_note(
            "The capital of France is **Paris**.\n\n#cloze\n",
            PathBuf::from("/tmp/test.md"),
        );
        let reg = empty_registry();
        let result = render_stock(&note, &reg, Path::new("/tmp/test.md"), Path::new("/tmp"));
        assert_eq!(result.fields[0].0, "Text");
        assert_eq!(result.fields[1].0, "Back Extra");
    }

    #[test]
    fn code_block_gets_highlighted() {
        let note = parse_note(
            "Look:\n\n```rust\nfn main() {}\n```\n",
            PathBuf::from("/tmp/test.md"),
        );
        let reg = empty_registry();
        let result = render_stock(&note, &reg, Path::new("/tmp/test.md"), Path::new("/tmp"));
        // Highlighted code should have inline styles, not a plain <pre><code>
        assert!(result.fields[0].1.contains("style="));
    }

    #[test]
    fn math_block_gets_mathjax() {
        let note = parse_note(
            "```math\nx^2\n```\n\n---\n\nAnswer\n",
            PathBuf::from("/tmp/test.md"),
        );
        let reg = empty_registry();
        let result = render_stock(&note, &reg, Path::new("/tmp/test.md"), Path::new("/tmp"));
        assert!(result.fields[0].1.contains("\\[x^2"));
    }

    #[test]
    fn no_back_section() {
        let note = parse_note(
            "Just a question.\n",
            PathBuf::from("/tmp/test.md"),
        );
        let reg = empty_registry();
        let result = render_stock(&note, &reg, Path::new("/tmp/test.md"), Path::new("/tmp"));
        assert_eq!(result.fields[0].0, "Front");
        assert!(result.fields[0].1.contains("question"));
        assert_eq!(result.fields[1].1, "");
    }
}
