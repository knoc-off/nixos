use crate::card::{Card, ClozeAlgorithm, NoteType, Tag as CardTag};
use crate::highlighter;
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Parser, Tag, TagEnd};
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#([\w:]+)").unwrap());

#[derive(Debug, Clone)]
enum ParserState {
    Normal,
    InCodeBlock(String, String),
}

#[derive(Debug)]
enum Section {
    Front,
    Back,
}

fn extract_tags(text: &str) -> Vec<CardTag> {
    TAG_REGEX
        .captures_iter(text)
        .map(|cap| CardTag::parse(&cap[1]))
        .collect()
}

fn remove_tag_markers(text: &str) -> String {
    TAG_REGEX.replace_all(text, "").to_string()
}

fn render_math(content: &str, _display: bool) -> String {
    format!("<p>\\[{}\\]</p>", content.trim())
}

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
            break;
        }
    }

    (has_bold, has_italic)
}

pub fn parse_card(markdown: &str, markdown_dir: Option<&Path>) -> (Card, Vec<String>) {
    let tags = extract_tags(markdown);

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

    let cloze_algorithm = cloze_algorithm.unwrap_or(ClozeAlgorithm::Increment);

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

    let generic_tags: Vec<String> = tags
        .iter()
        .filter_map(|t| match t {
            CardTag::Generic(s) => Some(s.clone()),
            _ => None,
        })
        .collect();

    let mut card = Card::new();
    card.note_type = note_type.clone();
    card.tags = generic_tags;

    let mut cloze_counter = 0;

    let mut front_content = String::new();
    let mut back_content = String::new();
    let mut current_section = Section::Front;
    let mut state = ParserState::Normal;
    let mut media_files = Vec::new();

    let parser = Parser::new(markdown);

    for event in parser {
        let content = match current_section {
            Section::Front => &mut front_content,
            Section::Back => &mut back_content,
        };

        match event {
            Event::Rule => {
                current_section = Section::Back;
            }
            Event::Start(Tag::Strong) => {
                if note_type == NoteType::Cloze {
                    let cloze_num = match cloze_algorithm {
                        ClozeAlgorithm::Increment => {
                            cloze_counter += 1;
                            cloze_counter
                        }
                        ClozeAlgorithm::Duo => 1,
                        ClozeAlgorithm::Auto => unreachable!(),
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
                        ClozeAlgorithm::Duo => 2,
                        ClozeAlgorithm::Auto => unreachable!(),
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
                    state = ParserState::Normal;
                }
            }
            Event::Text(text) => match &mut state {
                ParserState::InCodeBlock(_, code) => {
                    code.push_str(&text);
                }
                ParserState::Normal => {
                    let cleaned = remove_tag_markers(&text);
                    content.push_str(&cleaned);
                }
            },
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
                // Resolve and collect media file path
                let full_path = if let Some(dir) = markdown_dir {
                    dir.join(dest_url.as_ref())
                } else {
                    PathBuf::from(dest_url.as_ref())
                };

                if full_path.exists() {
                    media_files.push(full_path.to_string_lossy().to_string());
                } else {
                    eprintln!("Warning: Media file not found: {}", full_path.display());
                }

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
        &card.front,
        &card.back,
    );

    (card, media_files)
}
