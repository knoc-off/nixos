/// Note type for Anki cards
#[derive(Debug, Clone, PartialEq)]
pub enum NoteType {
    Basic,
    Cloze,
}

/// Represents a single flashcard (one file = one card)
#[derive(Debug, Clone)]
pub struct Card {
    pub front: String,
    pub back: String,
    pub note_type: NoteType,
    pub tags: Vec<String>,
    pub source_markdown: String,  // Original markdown source
    pub file_path: Option<String>, // File path for stable ID generation
}

impl Card {
    pub fn new() -> Self {
        dbg!("Creating new card");
        Self {
            front: String::new(),
            back: String::new(),
            note_type: NoteType::Basic,
            tags: Vec::new(),
            source_markdown: String::new(),
            file_path: None,
        }
    }
}

impl Default for Card {
    fn default() -> Self {
        Self::new()
    }
}
