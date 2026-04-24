//! Markdown → Card parser.
//!
//! Single file = single card. Front / back are split by the first `---`
//! horizontal rule. Tags are lexed out of the source before rendering:
//! system tags (see [`tag::SystemTag`]) are consumed, unknown `#word`
//! tokens pass through as Anki tags.
//!
//! Metadata written by `markid` itself (currently just `#id(...)`) is
//! nothing special to the parser — it's just another system tag, picked
//! up wherever it appears. By convention `markid fmt` writes it as the
//! first line of the file.

use crate::card::{Card, NoteType};
use crate::hash::content_hash;
use crate::highlighter;
use crate::tag::{ClozeAlgorithm, Parsed, SystemTag, TagParseError, parse_token};
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Parser, Tag, TagEnd};
use regex::Regex;
use std::sync::LazyLock;

/// Canonical regex for `#keyword` or `#keyword(args)` tokens.
///
/// Requires the token to start with an ASCII letter so we don't match things
/// like `#123` (CSS hex colors mentioned in prose). The rest of the
/// keyword may contain letters, digits, `_`, `-`, `:` (for Anki's `::`
/// hierarchy convention).
static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"#([A-Za-z][\w:\-]*(?:\([^)]*\))?)").expect("tag regex compiles")
});

/// Outcome of parsing a single `.md` file.
#[derive(Debug)]
pub struct ParseOutput {
    pub card: Card,
    /// Hard errors on system-looking tags (bad arg, malformed, ...). The
    /// caller decides whether to abort the sync or skip the file.
    pub errors: Vec<ParseError>,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ParseError {
    #[error("tag error: {0}")]
    Tag(#[from] TagParseError),
}

/// Parse a markdown file's full text into a [`Card`].
pub fn parse(source: &str) -> ParseOutput {
    let body = source;

    // 1. Lex every tag token out of the body (outside code blocks — the
    //    markdown pass below handles that by only examining Event::Text).
    let mut system_tags = Vec::new();
    let mut anki_tags = Vec::new();
    let mut errors = Vec::new();

    // 2. Figure out model + cloze algo before we render (the render pass
    //    needs to know whether to emit cloze markers).
    //    Do a preliminary scan of body for #cloze / #basic / #model tags.
    for tok in tokenize_tags(body) {
        if let Ok(sys) = SystemTag::from_str_checked(&tok) {
            // keep only model-affecting system tags in the pre-scan; the
            // real collection happens during rendering so source order is
            // preserved.
            if matches!(
                sys,
                SystemTag::Cloze(_) | SystemTag::Basic | SystemTag::Model(_)
            ) {
                system_tags.push(sys);
            }
        }
    }

    let (note_type, mut cloze_algorithm) = infer_model(&system_tags);
    if cloze_algorithm == ClozeAlgorithm::Auto {
        cloze_algorithm = resolve_auto_cloze(body);
    }

    // 3. Render markdown, stripping tags from output text as we go, and
    //    collecting anki-bound tags + media refs in source order. This
    //    pass also picks up `#id(...)` since it runs through every text
    //    span.
    let render = render_card(body, note_type, cloze_algorithm, &mut anki_tags, &mut errors);

    // 4. Second pass over tokens to pick up any system tags that weren't
    //    model-affecting (namely #id). We do this as a flat regex pass
    //    rather than reusing the render-time callback so that we see
    //    tokens which were inside code spans too — but in practice
    //    #id(...) always sits on its own line, so this is robust.
    for tok in tokenize_tags(body) {
        if let Ok(sys) = SystemTag::from_str_checked(&tok) {
            if matches!(sys, SystemTag::Id(_)) {
                system_tags.push(sys);
            }
        }
    }

    // 5. Extract #id from the collected system tags. First occurrence wins.
    let id = system_tags.iter().find_map(|t| match t {
        SystemTag::Id(n) => Some(n.clone()),
        _ => None,
    });

    // 6. Compute the current hash over the body. Version-bound via
    //    RENDER_VERSION.
    let current_hash = content_hash(body);

    let card = Card {
        id,
        current_hash,
        note_type,
        cloze_algorithm,
        front_html: render.front,
        back_html: render.back,
        anki_tags: dedupe_preserving_order(anki_tags),
        media_refs: render.media,
        stripped_source: body.to_string(),
    };

    ParseOutput { card, errors }
}

/// Extract the raw `#...` token strings from a block of text, without
/// classifying them. Matches our canonical tag regex.
fn tokenize_tags(text: &str) -> Vec<String> {
    TAG_REGEX
        .captures_iter(text)
        .map(|c| c[0].to_string())
        .collect()
}

/// Scan resolved system tags to decide note type + cloze algorithm.
/// Last write wins (explicit `#basic` after `#cloze` yields basic).
fn infer_model(system_tags: &[SystemTag]) -> (NoteType, ClozeAlgorithm) {
    let mut note_type = NoteType::Basic;
    let mut algo = ClozeAlgorithm::default();
    for t in system_tags {
        match t {
            SystemTag::Cloze(a) => {
                note_type = NoteType::Cloze;
                if let Some(a) = a {
                    algo = *a;
                }
            }
            SystemTag::Basic => {
                note_type = NoteType::Basic;
            }
            SystemTag::Model(m) => {
                note_type = NoteType::from(*m);
            }
            _ => {}
        }
    }
    (note_type, algo)
}

fn resolve_auto_cloze(body: &str) -> ClozeAlgorithm {
    let parser = Parser::new(body);
    let mut has_bold = false;
    let mut has_italic = false;
    for ev in parser {
        match ev {
            Event::Start(Tag::Strong) => has_bold = true,
            Event::Start(Tag::Emphasis) => has_italic = true,
            _ => {}
        }
        if has_bold && has_italic {
            return ClozeAlgorithm::Duo;
        }
    }
    ClozeAlgorithm::Increment
}

// ---------- rendering ----------

struct Rendered {
    front: String,
    back: String,
    media: Vec<String>,
}

#[derive(Debug)]
enum Section {
    Front,
    Back,
}

enum State {
    Normal,
    InCodeBlock { lang: String, buf: String },
}

fn render_card(
    body: &str,
    note_type: NoteType,
    cloze_algorithm: ClozeAlgorithm,
    anki_tags: &mut Vec<String>,
    errors: &mut Vec<ParseError>,
) -> Rendered {
    let mut front = String::new();
    let mut back = String::new();
    let mut media = Vec::new();
    let mut section = Section::Front;
    let mut state = State::Normal;
    let mut cloze_counter = 0u32;

    let parser = Parser::new(body);

    for event in parser {
        let out: &mut String = match section {
            Section::Front => &mut front,
            Section::Back => &mut back,
        };

        match event {
            Event::Rule => {
                section = Section::Back;
            }

            // ---- emphasis -> cloze / <strong>/<em>
            Event::Start(Tag::Strong) => match note_type {
                NoteType::Cloze => {
                    let n = next_cloze_num(cloze_algorithm, &mut cloze_counter, true);
                    out.push_str(&format!("{{{{c{n}::"));
                }
                NoteType::Basic => out.push_str("<strong>"),
            },
            Event::End(TagEnd::Strong) => match note_type {
                NoteType::Cloze => out.push_str("}}"),
                NoteType::Basic => out.push_str("</strong>"),
            },
            Event::Start(Tag::Emphasis) => match note_type {
                NoteType::Cloze => {
                    let n = next_cloze_num(cloze_algorithm, &mut cloze_counter, false);
                    out.push_str(&format!("{{{{c{n}::"));
                }
                NoteType::Basic => out.push_str("<em>"),
            },
            Event::End(TagEnd::Emphasis) => match note_type {
                NoteType::Cloze => out.push_str("}}"),
                NoteType::Basic => out.push_str("</em>"),
            },

            // ---- code blocks
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                state = State::InCodeBlock {
                    lang: lang.to_string(),
                    buf: String::new(),
                };
            }
            Event::End(TagEnd::CodeBlock) => {
                if let State::InCodeBlock { lang, buf } = std::mem::replace(&mut state, State::Normal) {
                    out.push_str(&render_code_block(&lang, &buf));
                }
            }
            Event::Start(Tag::CodeBlock(CodeBlockKind::Indented)) => {
                state = State::InCodeBlock {
                    lang: String::new(),
                    buf: String::new(),
                };
            }

            // ---- inline code
            Event::Code(code) => {
                let cleaned = strip_tags_from_text(&code, anki_tags, errors);
                out.push_str(&format!(
                    "<code style=\"font-size:0.85em;\">{}</code>",
                    escape_html(&cleaned),
                ));
            }

            // ---- text
            Event::Text(text) => match &mut state {
                State::InCodeBlock { buf, .. } => buf.push_str(&text),
                State::Normal => {
                    let cleaned = strip_tags_from_text(&text, anki_tags, errors);
                    out.push_str(&escape_html(&cleaned));
                }
            },

            Event::SoftBreak | Event::HardBreak => match &mut state {
                State::InCodeBlock { buf, .. } => buf.push('\n'),
                State::Normal => out.push_str("<br>"),
            },

            // ---- block structure
            Event::Start(Tag::Paragraph) => {
                // Don't emit yet — wait until we see actual content. We
                // do this by writing a sentinel and patching later.
                out.push_str("<p>");
            }
            Event::End(TagEnd::Paragraph) => {
                // Trim empty paragraphs (which happen when a whole paragraph
                // was just system tags stripped to nothing).
                if out.ends_with("<p>") {
                    out.truncate(out.len() - "<p>".len());
                } else {
                    out.push_str("</p>");
                }
            }
            Event::Start(Tag::Heading { level, .. }) => {
                out.push_str(&format!("<{}>", heading_tag(level)));
            }
            Event::End(TagEnd::Heading(level)) => {
                out.push_str(&format!("</{}>", heading_tag(level)));
            }
            Event::Start(Tag::List(None)) => out.push_str("<ul>"),
            Event::Start(Tag::List(Some(_))) => out.push_str("<ol>"),
            Event::End(TagEnd::List(ordered)) => {
                out.push_str(if ordered { "</ol>" } else { "</ul>" });
            }
            Event::Start(Tag::Item) => out.push_str("<li>"),
            Event::End(TagEnd::Item) => out.push_str("</li>"),
            Event::Start(Tag::BlockQuote(_)) => out.push_str("<blockquote>"),
            Event::End(TagEnd::BlockQuote(_)) => out.push_str("</blockquote>"),

            // ---- links
            Event::Start(Tag::Link { dest_url, .. }) => {
                out.push_str(&format!("<a href=\"{}\">", escape_html(&dest_url)));
            }
            Event::End(TagEnd::Link) => out.push_str("</a>"),

            // ---- images
            Event::Start(Tag::Image { dest_url, .. }) => {
                media.push(dest_url.to_string());
                // Anki expects just the media basename once stored; we
                // preserve the authored src for now and let the push layer
                // rewrite it when we know the final media filename.
                out.push_str(&format!("<img src=\"{}\" alt=\"", escape_html(&dest_url)));
            }
            Event::End(TagEnd::Image) => out.push_str("\">"),

            _ => {}
        }
    }

    Rendered {
        front: front.trim().to_string(),
        back: back.trim().to_string(),
        media,
    }
}

fn render_code_block(lang: &str, code: &str) -> String {
    // Languages prefixed with `_` are "known-but-unstyled" — user wants the
    // block rendered verbatim inside a <pre>. We still route through syntect
    // with the stripped language name so it picks up the right tokenizer.
    let (resolved_lang, force_plain) = if let Some(stripped) = lang.strip_prefix('_') {
        (stripped.to_string(), true)
    } else {
        (lang.to_string(), false)
    };

    match resolved_lang.as_str() {
        "math" | "latex" => format!("<p>\\[{}\\]</p>", code.trim()),
        _ => {
            let highlighted = if force_plain {
                escape_html(code)
            } else {
                highlighter::highlight_code(code, &resolved_lang)
            };
            format!(
                "<pre class=\"code\" style=\"font-size:0.85em;\
                 white-space:pre-wrap;word-wrap:break-word;\
                 overflow-wrap:break-word;\">\
                 <code>{highlighted}</code></pre>"
            )
        }
    }
}

fn heading_tag(level: HeadingLevel) -> &'static str {
    match level {
        HeadingLevel::H1 => "h1",
        HeadingLevel::H2 => "h2",
        HeadingLevel::H3 => "h3",
        HeadingLevel::H4 => "h4",
        HeadingLevel::H5 => "h5",
        HeadingLevel::H6 => "h6",
    }
}

fn next_cloze_num(algo: ClozeAlgorithm, counter: &mut u32, is_bold: bool) -> u32 {
    match algo {
        ClozeAlgorithm::Increment => {
            *counter += 1;
            *counter
        }
        ClozeAlgorithm::Duo => {
            if is_bold {
                1
            } else {
                2
            }
        }
        ClozeAlgorithm::Auto => unreachable!("Auto should have been resolved before rendering"),
    }
}

/// Within an Event::Text or Event::Code span, excise tag tokens from the
/// visible text while classifying each as system / anki / error. Anki tags
/// appended here (bottom-of-file tag lines in source order); system tags
/// were already consumed in the pre-scan pass so we just drop them.
fn strip_tags_from_text(
    text: &str,
    anki_tags: &mut Vec<String>,
    errors: &mut Vec<ParseError>,
) -> String {
    let mut out = String::with_capacity(text.len());
    let mut last = 0;
    for cap in TAG_REGEX.captures_iter(text) {
        let mat = cap.get(0).unwrap();
        out.push_str(&text[last..mat.start()]);
        last = mat.end();
        match parse_token(mat.as_str()) {
            Parsed::System(_) => {} // drop
            Parsed::AnkiTag(s) => anki_tags.push(s),
            Parsed::Error(e) => errors.push(ParseError::Tag(e)),
        }
    }
    out.push_str(&text[last..]);
    // Collapse whitespace left behind by stripping.
    out
}

fn dedupe_preserving_order(v: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    v.into_iter().filter(|x| seen.insert(x.clone())).collect()
}

fn escape_html(s: &str) -> String {
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

// Tiny shim so we can call SystemTag::from_str without pulling FromStr
// into each callsite's scope. The trait is still the authoritative impl.
impl SystemTag {
    fn from_str_checked(s: &str) -> Result<Self, TagParseError> {
        <Self as std::str::FromStr>::from_str(s)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_card_round_trip() {
        let src = "What is 2+2?\n\n---\n\n4 #math #arithmetic\n";
        let out = parse(src);
        assert_eq!(out.card.note_type, NoteType::Basic);
        assert!(out.card.front_html.contains("2+2"));
        assert!(out.card.back_html.contains('4'));
        assert_eq!(out.card.anki_tags, vec!["math", "arithmetic"]);
        assert!(out.card.id.is_none());
    }

    #[test]
    fn header_id_extracted() {
        let src = "#id(abcdef0123456789abcdef0123456789)\n\nfront\n---\nback\n";
        let out = parse(src);
        assert_eq!(
            out.card.id.as_deref(),
            Some("abcdef0123456789abcdef0123456789")
        );
    }

    #[test]
    fn cloze_marker_emitted() {
        let src = "#cloze\n\nThe capital of **France** is **Paris**.\n";
        let out = parse(src);
        assert_eq!(out.card.note_type, NoteType::Cloze);
        assert!(out.card.front_html.contains("{{c1::France}}"));
        assert!(out.card.front_html.contains("{{c2::Paris}}"));
    }

    #[test]
    fn cloze_duo_mixes_bold_italic() {
        let src = "#cloze(duo)\n\n**A** and *B*.\n";
        let out = parse(src);
        assert!(out.card.front_html.contains("{{c1::A}}"));
        assert!(out.card.front_html.contains("{{c2::B}}"));
    }

    #[test]
    fn anki_tags_preserved_from_trailing_line() {
        let src = "front\n---\nback\n\n#geography #europe #capitals\n";
        let out = parse(src);
        assert_eq!(
            out.card.anki_tags,
            vec!["geography", "europe", "capitals"]
        );
    }

    #[test]
    fn unknown_tag_passes_through_even_with_args() {
        // #math(foo) is unknown — the macro only recognises #model, etc.
        // Since it has args but no matching keyword, it should fail parse
        // as "unknown", not as "bad arg".
        let src = "front\n---\nback\n#math(foo)\n";
        let out = parse(src);
        assert!(out.errors.is_empty(), "errors: {:?}", out.errors);
        assert_eq!(out.card.anki_tags, vec!["math"]);
    }

    #[test]
    fn system_tag_error_surfaces() {
        // #basic takes no argument; giving one is an error.
        let src = "front\n---\nback\n#basic(oops)\n";
        let out = parse(src);
        assert!(!out.errors.is_empty());
    }

    #[test]
    fn code_block_tags_not_stripped() {
        let src = "```rust\nlet x = 1; // #not_a_tag\n```\n---\nback\n";
        let out = parse(src);
        // The #not_a_tag should not appear in anki_tags because it was
        // inside a code block (pulldown-cmark gives it as Event::Text under
        // InCodeBlock state, which we route straight into the code buffer).
        assert!(out.card.anki_tags.is_empty(), "got {:?}", out.card.anki_tags);
    }

    #[test]
    fn hash_is_deterministic() {
        let src = "hello\n---\nworld\n";
        let a = parse(src);
        let b = parse(src);
        assert_eq!(a.card.current_hash, b.card.current_hash);
    }

    #[test]
    fn id_line_does_not_leak_into_output() {
        let src = "#id(deadbeef00000001)\n\nfront\n---\nback\n";
        let out = parse(src);
        assert!(!out.card.front_html.contains("id(deadbeef"));
        assert!(!out.card.front_html.contains("#id"));
    }

    #[test]
    fn hyphenated_anki_tag() {
        let src = "front\n---\nback\n#basic-math #quick-review\n";
        let out = parse(src);
        assert_eq!(
            out.card.anki_tags,
            vec!["basic-math", "quick-review"]
        );
    }

    #[test]
    fn tag_only_paragraph_does_not_leave_empty_p() {
        // The #cloze on its own line would leave <p></p> without the fix.
        let src = "#cloze\n\nThe capital of **France**.\n";
        let out = parse(src);
        assert!(
            !out.card.front_html.contains("<p></p>"),
            "front_html was: {}",
            out.card.front_html
        );
    }
}
