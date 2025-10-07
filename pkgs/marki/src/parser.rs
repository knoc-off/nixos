use crate::card::{Card, ClozeAlgorithm, NoteType, Tag as CardTag};
use crate::highlighter;
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Parser, Tag, TagEnd};
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

<<<<<<< HEAD
static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#(\w+)").unwrap());
static IMG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"<img src="([^"]+)""#).unwrap());
=======
static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#([\w:]+)").unwrap());
>>>>>>> 3e039de (quick sync)

#[derive(Debug, Clone)]
enum ParserState {
    Normal,
    InCodeBlock(String, String), // (language, accumulated content)
}

#[derive(Debug)]
enum Section {
    Front,
    Back,
}

/// Extract and parse structured tags from markdown text
fn extract_tags(text: &str) -> Vec<CardTag> {
    TAG_REGEX
        .captures_iter(text)
        .map(|cap| CardTag::parse(&cap[1]))
        .collect()
}

/// Remove tag markers from text
fn remove_tag_markers(text: &str) -> String {
    TAG_REGEX.replace_all(text, "").to_string()
}

<<<<<<< HEAD
=======
/// Render math expression in MathJax format for Anki
/// Returns display math wrapped in \[...\]
fn render_math(content: &str, _display: bool) -> String {
    format!("<p>\\[{}\\]</p>", content.trim())
}

/// Render math expression using KaTeX (feature-gated)
/// Pre-renders to styled HTML
#[cfg(feature = "katex")]
fn render_katex(content: &str) -> String {
    katex::render_with_opts(
        content,
        katex::Opts::builder().display_mode(true).build().unwrap(),
    )
    .unwrap_or_else(|e| {
        eprintln!("KaTeX rendering failed: {}", e);
        // Fallback to MathJax format
        format!("<p>\\[{}\\]</p>", content.trim())
    })
}

>>>>>>> 3e039de (quick sync)
/// Detect which formatting types exist in the markdown (for cloze numbering)
fn detect_formatting(markdown: &str) -> (bool, bool) {
    let parser = Parser::new(markdown);
    let mut has_bold = false;
    let mut has_italic = false;

    for event in parser {
        match event {
            Event::Start(Tag::Strong) => has_bold = true,
            Event::Start(Tag::Emphasis) => has_italic = true,
            _ => {}
        }
        if has_bold && has_italic {
            break; // Found both, no need to continue
        }
    }

    (has_bold, has_italic)
}

/// Parse markdown content into a single card (one file = one card)
pub fn parse_card(markdown: &str) -> Card {
    let tags = extract_tags(markdown);

    // Determine note type and cloze algorithm from structured tags
    let mut cloze_algorithm = None;
    let mut note_type = NoteType::Basic;

    for tag in &tags {
        match tag {
            CardTag::Cloze { algo } => {
                note_type = NoteType::Cloze;
                cloze_algorithm = Some(algo.clone());
            }
            CardTag::Basic => {
                note_type = NoteType::Basic;
            }
            CardTag::Generic(_) => {}
        }
    }

    // Default to Increment if cloze but no algorithm specified
    let cloze_algorithm = cloze_algorithm.unwrap_or(ClozeAlgorithm::Increment);

    // For Auto mode, detect what formatting exists
    let cloze_algorithm = if matches!(cloze_algorithm, ClozeAlgorithm::Auto) {
        let (has_bold, has_italic) = detect_formatting(markdown);
        if has_bold && has_italic {
            ClozeAlgorithm::Duo
        } else {
            ClozeAlgorithm::Increment
        }
    } else {
        cloze_algorithm
    };

    // Extract generic tags for Anki
    let generic_tags: Vec<String> = tags
        .iter()
        .filter_map(|t| match t {
            CardTag::Generic(s) => Some(s.clone()),
            _ => None,
        })
        .collect();

<<<<<<< HEAD
    // Detect formatting types for cloze numbering
    let (has_bold, has_italic) = if note_type == NoteType::Cloze {
        detect_formatting(markdown)
    } else {
        (false, false)
    };

    // Determine cloze numbers based on what exists:
    // - If only italic: italic → c1
    // - If only bold: bold → c1
    // - If both: bold → c1, italic → c2
    let (cloze_bold, cloze_italic) = match (has_bold, has_italic) {
        (true, true) => (1, 2),
        (true, false) => (1, 0),
        (false, true) => (0, 1),
        (false, false) => (0, 0), // error? cloze without cloze...
    };

=======
>>>>>>> 3e039de (quick sync)
    let mut card = Card::new();
    card.note_type = note_type.clone();
    card.tags = generic_tags;

    // Cloze counter for Increment mode
    let mut cloze_counter = 0;

    let mut front_content = String::new();
    let mut back_content = String::new();
    let mut current_section = Section::Front;
    let mut state = ParserState::Normal;

    let parser = Parser::new(markdown);

    for event in parser {
        let content = match current_section {
            Section::Front => &mut front_content,
            Section::Back => &mut back_content,
        };

        match event {
            Event::Rule => {
                // First --- divides front from back
                current_section = Section::Back;
            }
            Event::Start(Tag::Strong) => {
                if note_type == NoteType::Cloze {
                    let cloze_num = match cloze_algorithm {
                        ClozeAlgorithm::Increment => {
                            cloze_counter += 1;
                            cloze_counter
                        }
                        ClozeAlgorithm::Duo => 1, // Bold is always c1
                        ClozeAlgorithm::Auto => unreachable!(), // Resolved earlier
                    };
                    content.push_str(&format!("{{{{c{}::", cloze_num));
                } else {
                    content.push_str("<strong>");
                }
            }
            Event::End(TagEnd::Strong) => {
                if note_type == NoteType::Cloze {
                    content.push_str("}}");
                } else {
                    content.push_str("</strong>");
                }
            }
            Event::Start(Tag::Emphasis) => {
                if note_type == NoteType::Cloze {
                    let cloze_num = match cloze_algorithm {
                        ClozeAlgorithm::Increment => {
                            cloze_counter += 1;
                            cloze_counter
                        }
                        ClozeAlgorithm::Duo => 2, // Italic is always c2
                        ClozeAlgorithm::Auto => unreachable!(), // Resolved earlier
                    };
                    content.push_str(&format!("{{{{c{}::", cloze_num));
                } else {
                    content.push_str("<em>");
                }
            }
            Event::End(TagEnd::Emphasis) => {
                if note_type == NoteType::Cloze {
                    content.push_str("}}");
                } else {
                    content.push_str("</em>");
                }
            }
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                state = ParserState::InCodeBlock(lang.to_string(), String::new());
            }
            Event::End(TagEnd::CodeBlock) => {
                if let ParserState::InCodeBlock(lang, code) = &state {
<<<<<<< HEAD
                    let highlighted = highlighter::highlight_code(code, lang);
                    content.push_str(&format!(
                        "<pre class=\"code\"><code>{}</code></pre>",
                        highlighted
                    ));
=======
                    let output = if lang.starts_with('_') {
                        let actual_lang = &lang[1..];
                        let highlighted = highlighter::highlight_code(code, actual_lang);
                        format!("<pre class=\"code\"><code>{}</code></pre>", highlighted)
                    } else {
                        match lang.as_str() {
                            "math" | "latex" => render_math(code, true),
                            #[cfg(feature = "katex")]
                            "katex" => render_katex(code),
                            _ => {
                                let highlighted = highlighter::highlight_code(code, lang);
                                format!("<pre class=\"code\"><code>{}</code></pre>", highlighted)
                            }
                        }
                    };
                    content.push_str(&output);
>>>>>>> 3e039de (quick sync)
                    state = ParserState::Normal;
                }
            }
            Event::Text(text) => {
                match &mut state {
                    ParserState::InCodeBlock(_, code) => {
                        code.push_str(&text);
                    }
                    ParserState::Normal => {
                        // Remove tag markers from text
                        let cleaned = remove_tag_markers(&text);
                        content.push_str(&cleaned);
                    }
                }
            }
            Event::SoftBreak | Event::HardBreak => match &mut state {
                ParserState::InCodeBlock(_, code) => {
                    code.push('\n');
                }
                ParserState::Normal => {
                    content.push_str("<br>");
                }
            },
            Event::Start(Tag::Paragraph) => {
                content.push_str("<p>");
            }
            Event::End(TagEnd::Paragraph) => {
                content.push_str("</p>");
            }
            Event::Start(Tag::Heading { level, .. }) => {
                let tag = match level {
                    HeadingLevel::H1 => "h1",
                    HeadingLevel::H2 => "h2",
                    HeadingLevel::H3 => "h3",
                    HeadingLevel::H4 => "h4",
                    HeadingLevel::H5 => "h5",
                    HeadingLevel::H6 => "h6",
                };
                content.push_str(&format!("<{}>", tag));
            }
            Event::End(TagEnd::Heading(level)) => {
                let tag = match level {
                    HeadingLevel::H1 => "h1",
                    HeadingLevel::H2 => "h2",
                    HeadingLevel::H3 => "h3",
                    HeadingLevel::H4 => "h4",
                    HeadingLevel::H5 => "h5",
                    HeadingLevel::H6 => "h6",
                };
                content.push_str(&format!("</{}>", tag));
            }
            Event::Start(Tag::List(None)) => {
                // Unordered list
                content.push_str("<ul>");
            }
            Event::Start(Tag::List(Some(_))) => {
                // Ordered list
                content.push_str("<ol>");
            }
            Event::End(TagEnd::List(false)) => {
                content.push_str("</ul>");
            }
            Event::End(TagEnd::List(true)) => {
                content.push_str("</ol>");
            }
            Event::Start(Tag::Item) => {
                content.push_str("<li>");
            }
            Event::End(TagEnd::Item) => {
                content.push_str("</li>");
            }
            Event::Start(Tag::BlockQuote(_)) => {
                content.push_str("<blockquote>");
            }
            Event::End(TagEnd::BlockQuote(_)) => {
                content.push_str("</blockquote>");
            }
            Event::Start(Tag::Link { dest_url, .. }) => {
                content.push_str(&format!("<a href=\"{}\">", dest_url));
            }
            Event::End(TagEnd::Link) => {
                content.push_str("</a>");
            }
            Event::Start(Tag::Image { dest_url, .. }) => {
<<<<<<< HEAD
=======
                let full_path = if let Some(dir) = markdown_dir {
                    dir.join(dest_url.as_ref())
                } else {
                    PathBuf::from(dest_url.as_ref())
                };

                if full_path.exists() {
                    card.media_files
                        .push(full_path.to_string_lossy().to_string());
                } else {
                    eprintln!("Warning: Media file not found: {}", full_path.display());
                }

>>>>>>> 3e039de (quick sync)
                content.push_str(&format!("<img src=\"{}\" alt=\"", dest_url));
            }
            Event::End(TagEnd::Image) => {
                content.push_str("\">");
            }
            Event::Code(code) => {
                let cleaned = remove_tag_markers(&code);
                content.push_str(&format!("<code>{}</code>", cleaned));
            }
            _ => {}
        }
    }

    card.source_markdown = markdown.replace('\n', "<br>"); // reversable?
    card.front = front_content.trim().to_string();
    card.back = back_content.trim().to_string();

    dbg!(
        "Parsed card",
        &card.note_type,
        &card.tags,
        card.front.len(),
        card.back.len()
    );

    card
}

/// Extract media file references from a card's HTML and resolve to full paths
pub fn extract_media_files(card: &Card, markdown_dir: Option<&Path>) -> Vec<String> {
    let mut media_files = Vec::new();

    // Search both front and back for image references
    for html in [&card.front, &card.back] {
        for capture in IMG_REGEX.captures_iter(html) {
            if let Some(src) = capture.get(1) {
                let filename = src.as_str();
                // dbg!("Found image reference", filename);

                // Resolve relative to markdown file's directory
                let full_path = if let Some(dir) = markdown_dir {
                    dir.join(filename)
                } else {
                    PathBuf::from(filename)
                };

                if full_path.exists() {
                    // dbg!("Media file exists", &full_path);
                    media_files.push(full_path.to_string_lossy().to_string());
                } else {
                    eprintln!("Warning: Media file not found: {}", full_path.display());
                }
            }
        }
    }

    media_files
}
