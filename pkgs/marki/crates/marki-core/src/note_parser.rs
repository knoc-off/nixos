//! Structural markdown parser.
//!
//! Unlike [`crate::parser`] (which renders directly to HTML for the
//! old pipeline), this module parses markdown into an ordered list of
//! typed [`Block`]s with both `text` and `html` representations. The
//! resulting [`Note`] is what Rhai model scripts receive and query.
//!
//! Tags are extracted into `Note::tags` and `Note::anki_tags` during
//! parsing and stripped from block content.

use crate::note::{Block, ListItem, Note, TagValue};
use crate::tag::{ClozeAlgorithm, Parsed, SystemTag, TAG_REGEX, parse_token};
use crate::util::escape_html;
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use std::collections::HashMap;
use std::path::PathBuf;

/// Parse a markdown source into a structural [`Note`].
///
/// This is the new entry point for the Rhai model pipeline. The
/// resulting `Note` contains typed blocks with inline HTML preserved
/// and tags extracted into structured maps.
pub fn parse_note(source: &str, source_path: PathBuf) -> Note {
    let mut blocks: Vec<Block> = Vec::new();
    let mut tags: HashMap<String, TagValue> = HashMap::new();
    let mut anki_tags: Vec<String> = Vec::new();
    let mut id: Option<String> = None;
    let mut model = "basic".to_string();
    let mut warnings: Vec<String> = Vec::new();

    // ---- Phase 1: Pre-scan tags that affect rendering.
    // We need to know if this is a cloze note BEFORE rendering starts
    // so that <strong>/<em> can be emitted as {{cN::}} markers.
    let cloze_pre = TAG_REGEX.captures_iter(source).find_map(|cap| {
        match parse_token(cap.get(0).unwrap().as_str()) {
            Parsed::System(SystemTag::Cloze(algo)) => Some(algo.unwrap_or_default()),
            _ => None,
        }
    });
    let is_cloze = cloze_pre.is_some();

    // Resolve Auto algorithm: need to know if both bold+italic exist.
    let resolved_cloze_algo = match cloze_pre {
        Some(ClozeAlgorithm::Auto) => {
            let opts = Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH;
            let mut has_strong = false;
            let mut has_em = false;
            for event in Parser::new_ext(source, opts) {
                match event {
                    Event::Start(Tag::Strong) => has_strong = true,
                    Event::Start(Tag::Emphasis) => has_em = true,
                    _ => {}
                }
                if has_strong && has_em { break; }
            }
            if has_strong && has_em { ClozeAlgorithm::Duo } else { ClozeAlgorithm::Increment }
        }
        Some(algo) => algo,
        None => ClozeAlgorithm::default(),
    };
    let mut cloze_counter: u32 = 0;

    // ---- Phase 2: Main parse.
    // State machine for accumulating block content.
    let mut state = ParseState::Idle;

    // Track when we're inside an image tag to accumulate alt text.
    // Holds (src, title, accumulated_alt_text).
    let mut in_image: Option<(String, String, String)> = None;

    let opts = Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH;
    let parser = Parser::new_ext(source, opts);

    for event in parser {
        match event {
            // ---- Thematic break (---)
            Event::Rule => {
                flush_block(&mut state, &mut blocks);
                blocks.push(Block::ThematicBreak);
            }

            // ---- Headings
            Event::Start(Tag::Heading { level, .. }) => {
                flush_block(&mut state, &mut blocks);
                state = ParseState::Heading {
                    level: heading_level_u8(level),
                    text: String::new(),
                    html: String::new(),
                };
            }
            Event::End(TagEnd::Heading(_)) => {
                flush_block(&mut state, &mut blocks);
            }

            // ---- Paragraphs
            Event::Start(Tag::Paragraph) => {
                // Don't flush if we're inside a blockquote — the paragraph
                // content belongs to the blockquote's buffers.
                if !matches!(state, ParseState::Blockquote { .. }) {
                    flush_block(&mut state, &mut blocks);
                    state = ParseState::Paragraph {
                        text: String::new(),
                        html: String::new(),
                    };
                }
            }
            Event::End(TagEnd::Paragraph) => {
                if !matches!(state, ParseState::Blockquote { .. }) {
                    flush_block(&mut state, &mut blocks);
                }
            }

            // ---- Lists
            Event::Start(Tag::List(start)) => {
                flush_block(&mut state, &mut blocks);
                state = ParseState::List {
                    ordered: start.is_some(),
                    items: Vec::new(),
                    current_item_text: String::new(),
                    current_item_html: String::new(),
                    html: if start.is_some() {
                        "<ol>".to_string()
                    } else {
                        "<ul>".to_string()
                    },
                };
            }
            Event::End(TagEnd::List(ordered)) => {
                // Close any pending item.
                if let ParseState::List {
                    ref mut items,
                    ref mut current_item_text,
                    ref mut current_item_html,
                    ref mut html,
                    ..
                } = state
                {
                    if !current_item_text.is_empty() || !current_item_html.is_empty() {
                        html.push_str("<li>");
                        html.push_str(current_item_html);
                        html.push_str("</li>");
                        items.push(ListItem {
                            text: std::mem::take(current_item_text),
                            html: std::mem::take(current_item_html),
                        });
                    }
                    html.push_str(if ordered { "</ol>" } else { "</ul>" });
                }
                flush_block(&mut state, &mut blocks);
            }
            Event::Start(Tag::Item) => {
                // Close previous item if any.
                if let ParseState::List {
                    ref mut items,
                    ref mut current_item_text,
                    ref mut current_item_html,
                    ref mut html,
                    ..
                } = state
                {
                    if !current_item_text.is_empty() || !current_item_html.is_empty() {
                        html.push_str("<li>");
                        html.push_str(current_item_html);
                        html.push_str("</li>");
                        items.push(ListItem {
                            text: std::mem::take(current_item_text),
                            html: std::mem::take(current_item_html),
                        });
                    }
                }
            }
            Event::End(TagEnd::Item) => {
                // Item content already accumulated; will be flushed on
                // next Start(Item) or End(List).
            }

            // ---- Blockquotes
            Event::Start(Tag::BlockQuote(_)) => {
                flush_block(&mut state, &mut blocks);
                state = ParseState::Blockquote {
                    text: String::new(),
                    html: String::new(),
                };
            }
            Event::End(TagEnd::BlockQuote(_)) => {
                flush_block(&mut state, &mut blocks);
            }

            // ---- Code blocks
            Event::Start(Tag::CodeBlock(kind)) => {
                flush_block(&mut state, &mut blocks);
                let lang = match kind {
                    CodeBlockKind::Fenced(info) => {
                        let l = info.split_whitespace().next().unwrap_or("").to_string();
                        if l.is_empty() { None } else { Some(l) }
                    }
                    CodeBlockKind::Indented => None,
                };
                state = ParseState::CodeBlock {
                    lang,
                    source: String::new(),
                };
            }
            Event::End(TagEnd::CodeBlock) => {
                flush_block(&mut state, &mut blocks);
            }

            // ---- Tables
            Event::Start(Tag::Table(_)) => {
                flush_block(&mut state, &mut blocks);
                state = ParseState::Table {
                    html: "<table>".to_string(),
                };
            }
            Event::End(TagEnd::Table) => {
                if let ParseState::Table { ref mut html } = state {
                    html.push_str("</tbody></table>");
                }
                flush_block(&mut state, &mut blocks);
            }
            Event::Start(Tag::TableHead) => push_html(&mut state, "<thead><tr>"),
            Event::End(TagEnd::TableHead) => push_html(&mut state, "</tr></thead><tbody>"),
            Event::Start(Tag::TableRow) => push_html(&mut state, "<tr>"),
            Event::End(TagEnd::TableRow) => push_html(&mut state, "</tr>"),
            Event::Start(Tag::TableCell) => push_html(&mut state, "<td>"),
            Event::End(TagEnd::TableCell) => push_html(&mut state, "</td>"),

            // ---- Inline formatting
            Event::Start(Tag::Strong) => {
                if is_cloze {
                    let n = next_cloze_num(&resolved_cloze_algo, true, &mut cloze_counter);
                    push_html(&mut state, &format!("{{{{c{n}::"));
                } else {
                    push_html(&mut state, "<strong>");
                }
            }
            Event::End(TagEnd::Strong) => {
                push_html(&mut state, if is_cloze { "}}" } else { "</strong>" });
            }
            Event::Start(Tag::Emphasis) => {
                if is_cloze {
                    let n = next_cloze_num(&resolved_cloze_algo, false, &mut cloze_counter);
                    push_html(&mut state, &format!("{{{{c{n}::"));
                } else {
                    push_html(&mut state, "<em>");
                }
            }
            Event::End(TagEnd::Emphasis) => {
                push_html(&mut state, if is_cloze { "}}" } else { "</em>" });
            }
            Event::Start(Tag::Strikethrough) => {
                push_html(&mut state, "<del>");
            }
            Event::End(TagEnd::Strikethrough) => {
                push_html(&mut state, "</del>");
            }
            Event::Start(Tag::Link { dest_url, title, .. }) => {
                let href = escape_html(&dest_url);
                if title.is_empty() {
                    push_html(&mut state, &format!("<a href=\"{href}\">"));
                } else {
                    let t = escape_html(&title);
                    push_html(&mut state, &format!("<a href=\"{href}\" title=\"{t}\">"));
                }
            }
            Event::End(TagEnd::Link) => {
                push_html(&mut state, "</a>");
            }
            Event::Start(Tag::Image { dest_url, title, .. }) => {
                in_image = Some((dest_url.to_string(), title.to_string(), String::new()));
            }
            Event::End(TagEnd::Image) => {
                if let Some((src, title, alt)) = in_image.take() {
                    let src = escape_html(&src);
                    let alt = escape_html(&alt);
                    if title.is_empty() {
                        push_html(&mut state, &format!("<img src=\"{src}\" alt=\"{alt}\">"));
                    } else {
                        let title = escape_html(&title);
                        push_html(&mut state, &format!("<img src=\"{src}\" alt=\"{alt}\" title=\"{title}\">"));
                    }
                }
            }

            // ---- Inline code
            Event::Code(code) => {
                let cleaned = strip_tags(&code, &mut anki_tags, &mut tags, &mut id, &mut model, &mut warnings);
                push_text(&mut state, &cleaned);
                push_html(
                    &mut state,
                    &format!("<code>{}</code>", escape_html(&cleaned)),
                );
            }

            // ---- Text content
            Event::Text(text) => {
                if let Some((_, _, ref mut alt)) = in_image {
                    // Inside an image — accumulate text as alt text.
                    alt.push_str(&text);
                } else {
                    match &mut state {
                        ParseState::CodeBlock { source, .. } => {
                            source.push_str(&text);
                        }
                        _ => {
                            let cleaned = strip_tags(&text, &mut anki_tags, &mut tags, &mut id, &mut model, &mut warnings);
                            push_text(&mut state, &cleaned);
                            push_html(&mut state, &escape_html(&cleaned));
                        }
                    }
                }
            }

            Event::SoftBreak | Event::HardBreak => {
                match &mut state {
                    ParseState::CodeBlock { source, .. } => source.push('\n'),
                    _ => {
                        push_text(&mut state, " ");
                        push_html(&mut state, "<br>");
                    }
                }
            }

            // Ignore everything else (footnotes, etc.)
            _ => {}
        }
    }

    // Flush any trailing block.
    flush_block(&mut state, &mut blocks);

    // Deduplicate anki tags preserving order.
    let mut seen = std::collections::HashSet::new();
    anki_tags.retain(|t| seen.insert(t.clone()));

    Note {
        id,
        model,
        cloze_algorithm: resolved_cloze_algo,
        blocks,
        tags,
        anki_tags,
        source: source.to_string(),
        source_path,
        warnings,
    }
}

// ---------- internal state ----------

enum ParseState {
    Idle,
    Heading {
        level: u8,
        text: String,
        html: String,
    },
    Paragraph {
        text: String,
        html: String,
    },
    List {
        ordered: bool,
        items: Vec<ListItem>,
        current_item_text: String,
        current_item_html: String,
        html: String,
    },
    CodeBlock {
        lang: Option<String>,
        source: String,
    },
    Blockquote {
        text: String,
        html: String,
    },
    Table {
        html: String,
    },
}

fn flush_block(
    state: &mut ParseState,
    blocks: &mut Vec<Block>,
) {
    let old = std::mem::replace(state, ParseState::Idle);
    match old {
        ParseState::Idle => {}
        ParseState::Heading { level, text, html } => {
            if !text.trim().is_empty() || !html.trim().is_empty() {
                blocks.push(Block::Heading { level, text: text.trim().to_string(), html: html.trim().to_string() });
            }
        }
        ParseState::Paragraph { text, html } => {
            // A paragraph that was entirely tags (stripped to empty) is dropped.
            if !text.trim().is_empty() || !html.trim().is_empty() {
                blocks.push(Block::Paragraph { text: text.trim().to_string(), html: html.trim().to_string() });
            }
        }
        ParseState::List { ordered, items, current_item_text, current_item_html, mut html } => {
            let mut items = items;
            if !current_item_text.is_empty() || !current_item_html.is_empty() {
                html.push_str("<li>");
                html.push_str(&current_item_html);
                html.push_str("</li>");
                items.push(ListItem {
                    text: current_item_text,
                    html: current_item_html,
                });
            }
            if !html.ends_with("</ol>") && !html.ends_with("</ul>") {
                html.push_str(if ordered { "</ol>" } else { "</ul>" });
            }
            if !items.is_empty() {
                blocks.push(Block::List { items, ordered, html });
            }
        }
        ParseState::CodeBlock { lang, source } => {
            blocks.push(Block::CodeBlock { lang, source });
        }
        ParseState::Blockquote { text, html } => {
            if !text.trim().is_empty() || !html.trim().is_empty() {
                blocks.push(Block::Blockquote { text: text.trim().to_string(), html: html.trim().to_string() });
            }
        }
        ParseState::Table { html } => {
            blocks.push(Block::Table { html });
        }
    }
}

fn push_html(state: &mut ParseState, s: &str) {
    match state {
        ParseState::Heading { html, .. } => html.push_str(s),
        ParseState::Paragraph { html, .. } => html.push_str(s),
        ParseState::List { current_item_html, .. } => current_item_html.push_str(s),
        ParseState::Blockquote { html, .. } => html.push_str(s),
        ParseState::Table { html } => html.push_str(s),
        ParseState::CodeBlock { source, .. } => source.push_str(s),
        ParseState::Idle => {}
    }
}

fn push_text(state: &mut ParseState, s: &str) {
    match state {
        ParseState::Heading { text, .. } => text.push_str(s),
        ParseState::Paragraph { text, .. } => text.push_str(s),
        ParseState::List { current_item_text, .. } => current_item_text.push_str(s),
        ParseState::Blockquote { text, .. } => text.push_str(s),
        ParseState::Table { .. } => {} // tables only track html
        ParseState::CodeBlock { .. } => {} // code blocks use source
        ParseState::Idle => {}
    }
}

/// Strip `#tag` and `#tag(arg)` tokens from a text span. Tags are
/// classified and routed to the appropriate collection.
///
/// Uses offset-walking over regex matches to build the result in O(n)
/// rather than repeated `String::replace` which is O(n*m).
fn strip_tags(
    text: &str,
    anki_tags: &mut Vec<String>,
    tags: &mut HashMap<String, TagValue>,
    id: &mut Option<String>,
    model: &mut String,
    warnings: &mut Vec<String>,
) -> String {
    let mut result = String::with_capacity(text.len());
    let mut last_end = 0;

    for cap in TAG_REGEX.captures_iter(text) {
        let m = cap.get(0).unwrap();
        let full = m.as_str(); // e.g. "#geography" or "#country(JAM)"
        let inner = &cap[1]; // e.g. "geography" or "country(JAM)"
        match parse_token(full) {
            Parsed::System(sys) => {
                result.push_str(&text[last_end..m.start()]);
                last_end = m.end();
                match sys {
                    SystemTag::Id(ref n) => {
                        if id.is_none() {
                            *id = Some(n.clone());
                        }
                    }
                    SystemTag::Model(ref mdl) => {
                        *model = mdl.clone();
                    }
                    SystemTag::Basic => {
                        *model = "basic".to_string();
                    }
                    SystemTag::Cloze(_) => {
                        *model = "cloze".to_string();
                    }
                }
            }
            Parsed::AnkiTag(kw) => {
                result.push_str(&text[last_end..m.start()]);
                last_end = m.end();
                if let Some(paren_start) = inner.find('(') {
                    let name = &inner[..paren_start];
                    let val = inner[paren_start + 1..].trim_end_matches(')');
                    tags.insert(name.to_string(), TagValue::Param(val.to_string()));
                } else {
                    tags.insert(kw.clone(), TagValue::Bool);
                }
                anki_tags.push(kw);
            }
            Parsed::Error(e) => {
                // Leave malformed tags in the text, but record a warning.
                warnings.push(format!("malformed tag: {full} — {e}"));
            }
        }
    }

    // Copy remaining text after the last stripped tag.
    result.push_str(&text[last_end..]);
    result
}

fn heading_level_u8(level: HeadingLevel) -> u8 {
    match level {
        HeadingLevel::H1 => 1,
        HeadingLevel::H2 => 2,
        HeadingLevel::H3 => 3,
        HeadingLevel::H4 => 4,
        HeadingLevel::H5 => 5,
        HeadingLevel::H6 => 6,
    }
}

/// Get the next cloze number for a bold or italic span.
fn next_cloze_num(algo: &ClozeAlgorithm, is_strong: bool, counter: &mut u32) -> u32 {
    match algo {
        ClozeAlgorithm::Increment => {
            *counter += 1;
            *counter
        }
        ClozeAlgorithm::Duo => if is_strong { 1 } else { 2 },
        ClozeAlgorithm::Auto => unreachable!("Auto must be resolved before rendering"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_front_back_split() {
        let src = "Question here\n\n---\n\nAnswer here\n";
        let note = parse_note(src, PathBuf::new());
        let secs = note.sections();
        assert_eq!(secs.len(), 2);
        assert_eq!(secs[0].len(), 1); // one paragraph
        assert_eq!(secs[1].len(), 1); // one paragraph
        assert_eq!(secs[0][0].text(), "Question here");
        assert_eq!(secs[1][0].text(), "Answer here");
    }

    #[test]
    fn tags_extracted_and_stripped() {
        let src = "Where is Jamaica?\n\n#geography #country(JAM) #model(geo)\n";
        let note = parse_note(src, PathBuf::new());
        assert_eq!(note.model, "geo");
        assert!(note.has_tag("geography"));
        assert_eq!(note.tag("country"), Some(&TagValue::Param("JAM".into())));
        // Tags stripped from paragraphs:
        let paras = note.paragraphs();
        assert_eq!(paras.len(), 1); // tag-only paragraph dropped
        assert_eq!(paras[0].text(), "Where is Jamaica?");
    }

    #[test]
    fn id_extracted() {
        let src = "#id(abc123def456) Where is it?\n\n---\n\nHere.\n";
        let note = parse_note(src, PathBuf::new());
        assert_eq!(note.id, Some("abc123def456".into()));
    }

    #[test]
    fn code_block_preserved() {
        let src = "Question\n\n```map\n[layers.base]\nfeatures = [\"country/DEU\"]\n```\n\n---\n\nAnswer\n";
        let note = parse_note(src, PathBuf::new());
        let cb = note.code_block("map");
        assert!(cb.is_some());
        assert!(cb.unwrap().source().unwrap().contains("[layers.base]"));
    }

    #[test]
    fn list_parsed() {
        let src = "- Fact one\n- Fact two\n- Fact three\n";
        let note = parse_note(src, PathBuf::new());
        let lists = note.lists();
        assert_eq!(lists.len(), 1);
        if let Block::List { items, ordered, .. } = &lists[0] {
            assert_eq!(items.len(), 3);
            assert!(!ordered);
            assert_eq!(items[0].text, "Fact one");
            assert_eq!(items[2].text, "Fact three");
        } else {
            panic!("expected List block");
        }
    }

    #[test]
    fn heading_parsed() {
        let src = "# Title\n\nParagraph text.\n";
        let note = parse_note(src, PathBuf::new());
        let h = note.heading(0);
        assert!(h.is_some());
        if let Block::Heading { level, text, .. } = h.unwrap() {
            assert_eq!(*level, 1);
            assert_eq!(text, "Title");
        }
    }

    #[test]
    fn inline_formatting_preserved_in_html() {
        let src = "This is **bold** and *italic*.\n";
        let note = parse_note(src, PathBuf::new());
        let p = note.paragraph(0).unwrap();
        assert!(p.html().contains("<strong>bold</strong>"));
        assert!(p.html().contains("<em>italic</em>"));
        // Plain text version has no tags:
        assert!(p.text().contains("bold"));
        assert!(!p.text().contains("<strong>"));
    }

    #[test]
    fn default_model_is_basic() {
        let src = "Simple card\n\n---\n\nAnswer\n";
        let note = parse_note(src, PathBuf::new());
        assert_eq!(note.model, "basic");
    }

    #[test]
    fn multiple_code_blocks() {
        let src = "```map\nmap source\n```\n\n```media\nmedia source\n```\n";
        let note = parse_note(src, PathBuf::new());
        assert!(note.code_block("map").is_some());
        assert!(note.code_block("media").is_some());
        assert!(note.code_block("nonexistent").is_none());
    }

    #[test]
    fn sections_multiple() {
        let src = "Section 0\n\n---\n\nSection 1\n\n---\n\nSection 2\n";
        let note = parse_note(src, PathBuf::new());
        let secs = note.sections();
        assert_eq!(secs.len(), 3);
    }

    #[test]
    fn blockquote_parsed() {
        let src = "> This is a quote.\n";
        let note = parse_note(src, PathBuf::new());
        let bqs = note.blockquotes();
        assert_eq!(bqs.len(), 1);
        assert_eq!(bqs[0].text(), "This is a quote.");
    }

    #[test]
    fn parametric_tag_in_tags_map() {
        let src = "Hello #deck(geography::hard) world\n";
        let note = parse_note(src, PathBuf::new());
        assert_eq!(
            note.tag("deck"),
            Some(&TagValue::Param("geography::hard".into()))
        );
        // "deck" shouldn't appear in anki_tags with the param
        assert!(note.anki_tags.contains(&"deck".to_string()));
    }

    #[test]
    fn empty_source() {
        let note = parse_note("", PathBuf::new());
        assert!(note.blocks.is_empty());
        assert_eq!(note.model, "basic");
        assert!(note.id.is_none());
    }

    #[test]
    fn image_alt_text() {
        let src = "![Alt text](image.png \"Title\")\n";
        let note = parse_note(src, PathBuf::new());
        let p = note.paragraph(0).unwrap();
        let html = p.html();
        assert!(
            html.contains("<img src=\"image.png\" alt=\"Alt text\" title=\"Title\">"),
            "unexpected html: {html}"
        );
    }

    #[test]
    fn image_without_title() {
        let src = "![Alt text](image.png)\n";
        let note = parse_note(src, PathBuf::new());
        let p = note.paragraph(0).unwrap();
        let html = p.html();
        assert!(
            html.contains("<img src=\"image.png\" alt=\"Alt text\">"),
            "unexpected html: {html}"
        );
        // No title attribute when title is empty.
        assert!(!html.contains("title="), "unexpected title in: {html}");
    }

    #[test]
    fn malformed_tag_produces_warning() {
        let src = "Hello #basic(invalid_arg) world\n";
        let note = parse_note(src, PathBuf::new());
        assert_eq!(note.warnings.len(), 1, "expected 1 warning, got: {:?}", note.warnings);
        assert!(
            note.warnings[0].contains("malformed tag: #basic(invalid_arg)"),
            "unexpected warning: {}",
            note.warnings[0]
        );
        // The malformed tag should remain in the text.
        let p = note.paragraph(0).unwrap();
        assert!(p.text().contains("#basic(invalid_arg)"), "malformed tag should stay in text");
    }

    #[test]
    fn no_warnings_for_valid_tags() {
        let src = "Hello #geography #country(JAM) world\n";
        let note = parse_note(src, PathBuf::new());
        assert!(note.warnings.is_empty(), "unexpected warnings: {:?}", note.warnings);
    }

    // ---- Cloze rendering tests ----

    #[test]
    fn cloze_increment_single_bold() {
        let note = parse_note(
            "The capital of France is **Paris**.\n\n#cloze\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("{{c1::Paris}}"), "got: {html}");
        assert!(!html.contains("<strong>"));
    }

    #[test]
    fn cloze_increment_multiple() {
        let note = parse_note(
            "Top three: **Russia**, **Canada**, **China**.\n\n#cloze\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("{{c1::Russia}}"), "got: {html}");
        assert!(html.contains("{{c2::Canada}}"), "got: {html}");
        assert!(html.contains("{{c3::China}}"), "got: {html}");
    }

    #[test]
    fn cloze_duo() {
        let note = parse_note(
            "**Berlin** is the capital of *Germany*.\n\n#cloze(duo)\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("{{c1::Berlin}}"), "got: {html}");
        assert!(html.contains("{{c2::Germany}}"), "got: {html}");
    }

    #[test]
    fn cloze_auto_only_bold_uses_increment() {
        let note = parse_note(
            "**A** and **B**.\n\n#cloze(auto)\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("{{c1::A}}"), "got: {html}");
        assert!(html.contains("{{c2::B}}"), "got: {html}");
    }

    #[test]
    fn cloze_auto_mixed_uses_duo() {
        let note = parse_note(
            "**A** is *B*.\n\n#cloze(auto)\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("{{c1::A}}"), "got: {html}");
        assert!(html.contains("{{c2::B}}"), "got: {html}");
    }

    #[test]
    fn non_cloze_keeps_strong_em() {
        let note = parse_note(
            "**bold** and *italic*.\n",
            PathBuf::new(),
        );
        let html = note.section_html(0);
        assert!(html.contains("<strong>bold</strong>"), "got: {html}");
        assert!(html.contains("<em>italic</em>"), "got: {html}");
    }

    #[test]
    fn cloze_algorithm_stored_on_note() {
        let note = parse_note("x\n\n#cloze(duo)\n", PathBuf::new());
        assert_eq!(note.model, "cloze");
        assert_eq!(note.cloze_algorithm, ClozeAlgorithm::Duo);
    }
}
