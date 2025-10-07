use marki_macros::ParseTag;
use strum::{Display, EnumString};

#[derive(Debug, Clone, PartialEq)]
pub enum NoteType {
    Basic,
    Cloze,
}

#[derive(Debug, Clone, Default, EnumString, Display)]
#[strum(serialize_all = "lowercase")]
pub enum ClozeAlgorithm {
    /// Auto-increment each cloze deletion (c1, c2, c3...)
    Increment,
    Duo,
    #[default]
    Auto,
}

#[derive(Debug, Clone, ParseTag)]
pub enum Tag {
    Cloze {
        algo: ClozeAlgorithm,
    },

    Basic,

    #[tag("*")]
    Generic(String),
}

#[derive(Debug, Clone)]
pub struct Card {
    pub front: String,
    pub back: String,
    pub note_type: NoteType,
    pub tags: Vec<String>,
    pub source_markdown: String,
    pub file_path: Option<String>,
    pub deck_name: String,
}

impl Card {
    pub fn new() -> Self {
        Self {
            front: String::new(),
            back: String::new(),
            note_type: NoteType::Basic,
            tags: Vec::new(),
            source_markdown: String::new(),
            file_path: None,
            deck_name: String::from("default"),
        }
    }
}

impl Default for Card {
    fn default() -> Self {
        Self::new()
    }
}
