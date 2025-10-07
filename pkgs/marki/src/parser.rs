use crate::card::{Card, NoteType};
use crate::highlighter;
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Parser, Tag, TagEnd};
use regex::Regex;
use std::sync::LazyLock;

static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#(\w+)").unwrap());

#[derive(Debug, Clone)]
enum ParserState {
    Normal,
    InStrong,     // Bold text - cloze c1
    InEmphasis,   // Italic text - cloze c2
    InCodeBlock(String), // Code block with language
}

#[derive(Debug)]
enum Section {
    Front,
    Back,
}

/// Extract tags from markdown text
fn extract_tags(text: &str) -> Vec<String> {
    TAG_REGEX
        .captures_iter(text)
        .map(|cap| cap[1].to_string())
        .collect()
}

/// Remove tag markers from text
fn remove_tag_markers(text: &str) -> String {
    TAG_REGEX.replace_all(text, "").to_string()
}

/// Parse markdown content into a single card (one file = one card)
pub fn parse_card(markdown: &str) -> Card {
    dbg!("Starting to parse card", markdown.len());

    // Extract tags first
    let tags = extract_tags(markdown);
    dbg!("Extracted tags", &tags);

    // Determine note type from tags
    let note_type = if tags.iter().any(|t| t == "cloze") {
        dbg!("Card is cloze type");
        NoteType::Cloze
    } else {
        dbg!("Card is basic type");
        NoteType::Basic
    };

    // Remove type tags (cloze, basic) from tags list, keep others
    let tags: Vec<String> = tags
        .into_iter()
        .filter(|t| t != "cloze" && t != "basic")
        .collect();
    dbg!("Final tags", &tags);

    let mut card = Card::new();
    card.note_type = note_type.clone();
    card.tags = tags;

    let mut front_content = String::new();
    let mut back_content = String::new();
    let mut current_section = Section::Front;
    let mut state = ParserState::Normal;
    let mut code_content = String::new();
    let mut cloze_counter = 0;

    let parser = Parser::new(markdown);

    for event in parser {
        let content = match current_section {
            Section::Front => &mut front_content,
            Section::Back => &mut back_content,
        };

        match event {
            Event::Rule => {
                // First --- divides front from back
                dbg!("Found horizontal rule, switching to back section");
                current_section = Section::Back;
            }
            Event::Start(Tag::Strong) => {
                dbg!("Starting bold text");
                state = ParserState::InStrong;
                if note_type == NoteType::Cloze {
                    cloze_counter += 1;
                    content.push_str(&format!("{{{{c{}::", cloze_counter));
                } else {
                    content.push_str("<strong>");
                }
            }
            Event::End(TagEnd::Strong) => {
                dbg!("Ending bold text");
                if note_type == NoteType::Cloze {
                    match current_section {
                        Section::Front => front_content.push_str("}}"),
                        Section::Back => back_content.push_str("}}"),
                    }
                } else {
                    content.push_str("</strong>");
                }
                state = ParserState::Normal;
            }
            Event::Start(Tag::Emphasis) => {
                dbg!("Starting italic text");
                state = ParserState::InEmphasis;
                if note_type == NoteType::Cloze {
                    cloze_counter += 1;
                    content.push_str(&format!("{{{{c{}::", cloze_counter));
                } else {
                    content.push_str("<em>");
                }
            }
            Event::End(TagEnd::Emphasis) => {
                dbg!("Ending italic text");
                if note_type == NoteType::Cloze {
                    match current_section {
                        Section::Front => front_content.push_str("}}"),
                        Section::Back => back_content.push_str("}}"),
                    }
                } else {
                    content.push_str("</em>");
                }
                state = ParserState::Normal;
            }
            Event::Start(Tag::CodeBlock(CodeBlockKind::Fenced(lang))) => {
                let language = lang.to_string();
                dbg!("Starting code block", &language);
                state = ParserState::InCodeBlock(language);
                code_content.clear();
            }
            Event::End(TagEnd::CodeBlock) => {
                if let ParserState::InCodeBlock(lang) = &state {
                    dbg!("Ending code block, highlighting");
                    let highlighted = highlighter::highlight_code(&code_content, lang);
                    content.push_str(&format!("<pre class=\"code\"><code>{}</code></pre>", highlighted));
                    code_content.clear();
                    state = ParserState::Normal;
                }
            }
            Event::Text(text) => {
                match &state {
                    ParserState::InCodeBlock(_) => {
                        code_content.push_str(&text);
                    }
                    _ => {
                        // Remove tag markers from text
                        let cleaned = remove_tag_markers(&text);
                        content.push_str(&cleaned);
                    }
                }
            }
            Event::SoftBreak | Event::HardBreak => {
                match &state {
                    ParserState::InCodeBlock(_) => {
                        code_content.push('\n');
                    }
                    _ => {
                        content.push_str("<br>");
                    }
                }
            }
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
                content.push_str(&format!("<img src=\"{}\" alt=\"", dest_url));
            }
            Event::End(TagEnd::Image) => {
                content.push_str("\">");
            }
            Event::Code(code) => {
                // Inline code
                let cleaned = remove_tag_markers(&code);
                content.push_str(&format!("<code>{}</code>", cleaned));
            }
            _ => {}
        }
    }

    card.front = front_content.trim().to_string();
    card.back = back_content.trim().to_string();

    dbg!("Parsed card", &card.note_type, &card.tags, card.front.len(), card.back.len());
    card
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_cards() {
        let markdown = r#"# Card 1

Front content

---

# Card 2

More content
"#;
        let cards = parse_cards(markdown);
        assert_eq!(cards.len(), 2);
        assert_eq!(cards[0].title, Some("Card 1".to_string()));
        assert_eq!(cards[1].title, Some("Card 2".to_string()));
    }

    #[test]
    fn test_parse_cloze() {
        let markdown = r#"# Test

**bold** and *italic*
"#;
        let cards = parse_cards(markdown);
        assert_eq!(cards.len(), 1);
        assert!(cards[0].is_cloze);
        assert!(cards[0].front.contains("{{c1::"));
        assert!(cards[0].front.contains("{{c2::"));
    }
}
