//! Card model — what a single `.md` file, once parsed, represents in Anki.

use crate::tag::{ClozeAlgorithm, ModelKind, NoteId};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NoteType {
    Basic,
    Cloze,
}

impl From<ModelKind> for NoteType {
    fn from(m: ModelKind) -> Self {
        match m {
            ModelKind::Basic => NoteType::Basic,
            ModelKind::Cloze => NoteType::Cloze,
        }
    }
}

/// A fully parsed + rendered card, ready to diff against Anki and push.
#[derive(Debug, Clone)]
pub struct Card {
    /// Our stable identity (value of `#id(...)`). `None` if this card has
    /// never been through the formatter.
    pub id: Option<NoteId>,
    /// Freshly computed content hash (version-bound). The source of
    /// truth; compared against whatever the Anki note holds in its
    /// `Marki_Hash` field.
    pub current_hash: String,
    /// Which note type this card uses.
    pub note_type: NoteType,
    /// Cloze algorithm used while rendering (only meaningful for `Cloze`).
    pub cloze_algorithm: ClozeAlgorithm,
    /// Rendered HTML for the front / question / cloze text field.
    pub front_html: String,
    /// Rendered HTML for the back / extra field. May be empty for cloze.
    pub back_html: String,
    /// Anki-bound tags (pass-through `#word` tokens) in source order.
    pub anki_tags: Vec<String>,
    /// Paths of `![](...)` images we saw (verbatim from the source, caller
    /// resolves them against the `.md` file's directory).
    pub media_refs: Vec<String>,
    /// Raw markdown content after system tags have been stripped.
    pub stripped_source: String,
}
