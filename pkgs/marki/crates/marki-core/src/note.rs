//! Structural note representation.
//!
//! A `Note` is the **parsed** form of one markdown file — an ordered
//! list of typed blocks, extracted tags, and metadata. It's the input
//! that a Rhai model script receives and queries to produce card
//! fields.
//!
//! Unlike `Card` (which holds pre-rendered HTML for a single front/back
//! pair), `Note` preserves the document structure so scripts can
//! rearrange content into arbitrarily many card faces.

use std::collections::HashMap;
use std::path::PathBuf;

use crate::tag::ClozeAlgorithm;
use crate::util::escape_html;

/// A parsed note, ready for a model script to inspect.
#[derive(Debug, Clone)]
pub struct Note {
    /// Stable identity (`#id(hex)`). `None` if unformatted.
    pub id: Option<String>,
    /// Model name from `#model(name)`. Defaults to `"basic"`.
    pub model: String,
    /// Cloze algorithm from `#cloze(algo)`. Only meaningful when `model == "cloze"`.
    pub cloze_algorithm: ClozeAlgorithm,
    /// Ordered list of every block in the document.
    pub blocks: Vec<Block>,
    /// System + parametric tags: `#country(JAM)` → `("country", Param("JAM"))`.
    /// Boolean tags like `#geography` → `("geography", Bool)`.
    pub tags: HashMap<String, TagValue>,
    /// Pass-through Anki tags (bare `#word` tokens that aren't system tags).
    pub anki_tags: Vec<String>,
    /// Raw markdown source.
    pub source: String,
    /// Path to the `.md` file (for error messages and relative media resolution).
    pub source_path: PathBuf,
    /// Non-fatal warnings collected during parsing (e.g. malformed tags).
    pub warnings: Vec<String>,
}

/// Value of a tag.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TagValue {
    /// Bare tag: `#geography`.
    Bool,
    /// Parametric tag: `#country(JAM)`.
    Param(String),
}

/// One structural block of the document.
#[derive(Debug, Clone)]
pub enum Block {
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
        items: Vec<ListItem>,
        ordered: bool,
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
    ThematicBreak,
    Table {
        html: String,
    },
}

/// One item inside a list block.
#[derive(Debug, Clone)]
pub struct ListItem {
    pub text: String,
    pub html: String,
}

// ---- Note convenience methods ----

impl Note {
    /// Split blocks at `ThematicBreak` into sections. Section 0 is
    /// everything before the first `---`; section 1 is everything
    /// after the first `---` and before the second; etc.
    pub fn sections(&self) -> Vec<Vec<&Block>> {
        let mut sections: Vec<Vec<&Block>> = vec![vec![]];
        for b in &self.blocks {
            match b {
                Block::ThematicBreak => sections.push(vec![]),
                _ => {
                    sections.last_mut().unwrap().push(b);
                }
            }
        }
        sections
    }

    /// Get one section by index. Returns empty slice if out of range.
    pub fn section(&self, n: usize) -> Vec<&Block> {
        self.sections().into_iter().nth(n).unwrap_or_default()
    }

    /// All paragraphs in document order.
    pub fn paragraphs(&self) -> Vec<&Block> {
        self.blocks
            .iter()
            .filter(|b| matches!(b, Block::Paragraph { .. }))
            .collect()
    }

    /// Nth paragraph (0-indexed).
    pub fn paragraph(&self, n: usize) -> Option<&Block> {
        self.paragraphs().into_iter().nth(n)
    }

    /// All headings in document order.
    pub fn headings(&self) -> Vec<&Block> {
        self.blocks
            .iter()
            .filter(|b| matches!(b, Block::Heading { .. }))
            .collect()
    }

    /// Nth heading (0-indexed).
    pub fn heading(&self, n: usize) -> Option<&Block> {
        self.headings().into_iter().nth(n)
    }

    /// All code blocks with a specific lang token.
    pub fn code_blocks(&self, lang: &str) -> Vec<&Block> {
        self.blocks
            .iter()
            .filter(|b| matches!(b, Block::CodeBlock { lang: Some(l), .. } if l == lang))
            .collect()
    }

    /// First code block with a specific lang token.
    pub fn code_block(&self, lang: &str) -> Option<&Block> {
        self.code_blocks(lang).into_iter().next()
    }

    /// All lists in document order.
    pub fn lists(&self) -> Vec<&Block> {
        self.blocks
            .iter()
            .filter(|b| matches!(b, Block::List { .. }))
            .collect()
    }

    /// All blockquotes in document order.
    pub fn blockquotes(&self) -> Vec<&Block> {
        self.blocks
            .iter()
            .filter(|b| matches!(b, Block::Blockquote { .. }))
            .collect()
    }

    /// Get a tag value by name.
    pub fn tag(&self, name: &str) -> Option<&TagValue> {
        self.tags.get(name)
    }

    /// Check if a tag exists (boolean or parametric).
    pub fn has_tag(&self, name: &str) -> bool {
        self.tags.contains_key(name)
    }

    /// Concatenate all blocks' HTML in a section.
    pub fn section_html(&self, n: usize) -> String {
        let section = self.section(n);
        let mut html = String::new();
        for block in section {
            if !html.is_empty() {
                html.push('\n');
            }
            html.push_str(&block_html(block));
        }
        html
    }

    /// Full body HTML (all blocks concatenated).
    pub fn body_html(&self) -> String {
        let mut html = String::new();
        for block in &self.blocks {
            if matches!(block, Block::ThematicBreak) {
                continue;
            }
            if !html.is_empty() {
                html.push('\n');
            }
            html.push_str(&block_html(block));
        }
        html
    }
}

// ---- Block accessors ----

impl Block {
    /// Plain-text content of this block.
    pub fn text(&self) -> &str {
        match self {
            Block::Heading { text, .. } => text,
            Block::Paragraph { text, .. } => text,
            Block::List { .. } => "",
            Block::CodeBlock { source, .. } => source,
            Block::Blockquote { text, .. } => text,
            Block::ThematicBreak => "",
            Block::Table { .. } => "",
        }
    }

    /// HTML content of this block (without wrapping element).
    pub fn html(&self) -> &str {
        match self {
            Block::Heading { html, .. } => html,
            Block::Paragraph { html, .. } => html,
            Block::List { html, .. } => html,
            Block::CodeBlock { source, .. } => source,
            Block::Blockquote { html, .. } => html,
            Block::ThematicBreak => "",
            Block::Table { html, .. } => html,
        }
    }

    /// Lang token for code blocks; `None` for everything else.
    pub fn lang(&self) -> Option<&str> {
        match self {
            Block::CodeBlock { lang, .. } => lang.as_deref(),
            _ => None,
        }
    }

    /// Source code for code blocks; `None` for everything else.
    pub fn source(&self) -> Option<&str> {
        match self {
            Block::CodeBlock { source, .. } => Some(source),
            _ => None,
        }
    }
}

/// Get the HTML representation of a block, wrapped in appropriate element.
fn block_html(block: &Block) -> String {
    match block {
        Block::Heading { html, level, .. } => {
            format!("<h{level}>{html}</h{level}>")
        }
        Block::Paragraph { html, .. } => {
            format!("<p>{html}</p>")
        }
        Block::List { html, .. } => html.clone(),
        Block::CodeBlock { lang, source } => {
            if let Some(l) = lang {
                format!("<pre><code class=\"language-{l}\">{}</code></pre>", escape_html(source))
            } else {
                format!("<pre><code>{}</code></pre>", escape_html(source))
            }
        }
        Block::Blockquote { html, .. } => {
            format!("<blockquote>{html}</blockquote>")
        }
        Block::ThematicBreak => "<hr>".to_string(),
        Block::Table { html } => html.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_note() -> Note {
        Note {
            id: Some("abc123".into()),
            model: "basic".into(),
            blocks: vec![
                Block::Paragraph {
                    text: "Question text".into(),
                    html: "Question text".into(),
                },
                Block::CodeBlock {
                    lang: Some("map".into()),
                    source: "[layers.base]\nfeatures = [\"country/DEU\"]".into(),
                },
                Block::ThematicBreak,
                Block::Paragraph {
                    text: "Answer text".into(),
                    html: "Answer text".into(),
                },
                Block::List {
                    items: vec![
                        ListItem { text: "Fact 1".into(), html: "Fact 1".into() },
                        ListItem { text: "Fact 2".into(), html: "Fact 2".into() },
                    ],
                    ordered: false,
                    html: "<ul><li>Fact 1</li><li>Fact 2</li></ul>".into(),
                },
            ],
            tags: {
                let mut m = HashMap::new();
                m.insert("country".into(), TagValue::Param("DEU".into()));
                m.insert("geography".into(), TagValue::Bool);
                m
            },
            anki_tags: vec!["geography".into(), "europe".into()],
            cloze_algorithm: ClozeAlgorithm::default(),
            source: String::new(),
            source_path: PathBuf::new(),
            warnings: Vec::new(),
        }
    }

    #[test]
    fn sections_split_at_break() {
        let n = sample_note();
        let secs = n.sections();
        assert_eq!(secs.len(), 2);
        assert_eq!(secs[0].len(), 2); // paragraph + code block
        assert_eq!(secs[1].len(), 2); // paragraph + list
    }

    #[test]
    fn section_by_index() {
        let n = sample_note();
        assert_eq!(n.section(0).len(), 2);
        assert_eq!(n.section(1).len(), 2);
        assert!(n.section(5).is_empty()); // out of range
    }

    #[test]
    fn paragraphs_filters_correctly() {
        let n = sample_note();
        assert_eq!(n.paragraphs().len(), 2);
    }

    #[test]
    fn code_block_by_lang() {
        let n = sample_note();
        assert!(n.code_block("map").is_some());
        assert!(n.code_block("nonexistent").is_none());
    }

    #[test]
    fn tag_access() {
        let n = sample_note();
        assert_eq!(n.tag("country"), Some(&TagValue::Param("DEU".into())));
        assert_eq!(n.tag("geography"), Some(&TagValue::Bool));
        assert!(n.has_tag("geography"));
        assert!(!n.has_tag("missing"));
    }

    #[test]
    fn section_html_concatenates() {
        let n = sample_note();
        let front = n.section_html(0);
        assert!(front.contains("<p>Question text</p>"));
        assert!(front.contains("<pre><code"));
    }

    #[test]
    fn body_html_skips_breaks() {
        let n = sample_note();
        let html = n.body_html();
        assert!(!html.contains("<hr>"));
        assert!(html.contains("Question text"));
        assert!(html.contains("Answer text"));
    }

    #[test]
    fn block_accessors() {
        let b = Block::Heading {
            level: 2,
            text: "Title".into(),
            html: "<strong>Title</strong>".into(),
        };
        assert_eq!(b.text(), "Title");
        assert_eq!(b.html(), "<strong>Title</strong>");
        assert!(b.lang().is_none());
    }

    #[test]
    fn code_block_accessors() {
        let b = Block::CodeBlock {
            lang: Some("map".into()),
            source: "toml stuff".into(),
        };
        assert_eq!(b.lang(), Some("map"));
        assert_eq!(b.source(), Some("toml stuff"));
    }
}
