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
}

impl Card {
    pub fn new() -> Self {
        dbg!("Creating new card");
        Self {
            front: String::new(),
            back: String::new(),
            note_type: NoteType::Basic,
            tags: Vec::new(),
        }
    }
}

impl Default for Card {
    fn default() -> Self {
        Self::new()
    }
}
