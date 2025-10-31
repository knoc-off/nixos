use crate::card::{Card, NoteType, Tag as CardTag};
use pulldown_cmark::{Event, Parser, Tag};
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

static TAG_REGEX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"#([\w:]+)").unwrap());

fn extract_tags(text: &str) -> Vec<CardTag> {
    TAG_REGEX
        .captures_iter(text)
        .map(|cap| CardTag::parse(&cap[1]))
        .collect()
}

fn remove_tag_markers(text: &str) -> String {
    TAG_REGEX.replace_all(text, "").to_string()
}

pub fn parse_card(markdown: &str, markdown_dir: Option<&Path>) -> (Card, Vec<String>) {
    let tags = extract_tags(markdown);

    let mut note_type = NoteType::Basic;

    for tag in &tags {
        match tag {
            CardTag::Cloze { .. } => {
                note_type = NoteType::Cloze;
            }
            CardTag::Basic => {
                note_type = NoteType::Basic;
            }
            CardTag::Generic(_) => {}
        }
    }

    let generic_tags: Vec<String> = tags
        .iter()
        .filter_map(|t| match t {
            CardTag::Generic(s) => Some(s.clone()),
            _ => None,
        })
        .collect();

    // Simple split on first --- to get front/back
    let parts: Vec<&str> = markdown.splitn(2, "\n---\n").collect();
    let front_md = parts.first().unwrap_or(&"").trim();
    let back_md = parts.get(1).unwrap_or(&"").trim();

    // Remove tags from markdown for cleaner rendering
    let front_clean = remove_tag_markers(front_md);
    let back_clean = remove_tag_markers(back_md);

    // Extract media files from images
    let mut media_files = Vec::new();
    let parser = Parser::new(markdown);

    for event in parser {
        if let Event::Start(Tag::Image { dest_url, .. }) = event {
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
        }
    }

    let mut card = Card::new();
    card.note_type = note_type;
    card.tags = generic_tags;
    card.source_markdown = markdown.to_string();
    // Keep raw markdown - <pre> tags will preserve formatting
    card.front = front_clean;
    card.back = back_clean;

    dbg!(
        "Parsed card",
        &card.note_type,
        &card.tags,
        &card.front,
        &card.back,
    );

    (card, media_files)
}
