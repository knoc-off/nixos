/// Note type for Anki cards
#[derive(Debug, Clone, PartialEq)]
pub enum NoteType {
    Basic,
    Cloze,
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
        // dbg!("Creating new card");
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
