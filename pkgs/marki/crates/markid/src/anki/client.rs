//! AnkiConnect HTTP client.

use super::model::{
    MARKER_TAG, ManagedNote, ModelKind, full_tag_set, hash_from_tags, id_from_tags, strip_marker,
};
use serde_json::{Value, json};
use std::time::Duration;

pub const ANKICONNECT_VERSION: u32 = 6;

#[derive(Debug, thiserror::Error)]
pub enum AnkiError {
    #[error("transport: {0}")]
    Transport(#[from] reqwest::Error),
    #[error("ankiconnect response missing error or result field")]
    Malformed,
    #[error("ankiconnect: {0}")]
    Remote(String),
    #[error("unexpected result shape: {0}")]
    Shape(String),
}

pub struct AnkiConnect {
    client: reqwest::blocking::Client,
    endpoint: String,
}

impl AnkiConnect {
    pub fn new(endpoint: impl Into<String>) -> Result<Self, AnkiError> {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;
        Ok(Self {
            client,
            endpoint: endpoint.into(),
        })
    }

    pub fn call(&self, action: &str, params: Value) -> Result<Value, AnkiError> {
        // AnkiConnect's JSON schema requires `params` to be an object, so
        // swap `null` for `{}` when a caller didn't supply any.
        let params = if params.is_null() {
            serde_json::json!({})
        } else {
            params
        };
        let body = json!({
            "action": action,
            "version": ANKICONNECT_VERSION,
            "params": params,
        });
        let resp = self
            .client
            .post(&self.endpoint)
            .json(&body)
            .send()?
            .error_for_status()?
            .json::<Value>()?;

        let err = resp.get("error").ok_or(AnkiError::Malformed)?;
        if !err.is_null() {
            return Err(AnkiError::Remote(
                err.as_str().unwrap_or("unknown").to_string(),
            ));
        }
        let result = resp.get("result").ok_or(AnkiError::Malformed)?;
        Ok(result.clone())
    }

    pub fn ping(&self) -> Result<u32, AnkiError> {
        let v = self.call("version", Value::Null)?;
        v.as_u64()
            .map(|n| n as u32)
            .ok_or_else(|| AnkiError::Shape("version was not a number".into()))
    }

    // ---------- deck management ----------

    pub fn ensure_deck(&self, deck: &str) -> Result<(), AnkiError> {
        self.call("createDeck", json!({ "deck": deck }))?;
        Ok(())
    }

    // ---------- note queries ----------

    pub fn find_notes(&self, query: &str) -> Result<Vec<i64>, AnkiError> {
        let v = self.call("findNotes", json!({ "query": query }))?;
        serde_json::from_value(v).map_err(|e| AnkiError::Shape(format!("findNotes: {e}")))
    }

    /// Fetch every managed note (`tag:marki`) along with its marki id,
    /// hash, deck, and card ids.
    pub fn managed_notes(&self) -> Result<Vec<ManagedNote>, AnkiError> {
        let ids = self.find_notes(&format!("tag:{MARKER_TAG}"))?;
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let notes = self.call("notesInfo", json!({ "notes": ids }))?;
        let notes: Vec<Value> = serde_json::from_value(notes)
            .map_err(|e| AnkiError::Shape(format!("notesInfo: {e}")))?;

        // Resolve decks via cardsInfo in one batch.
        let mut first_cards: Vec<i64> = Vec::with_capacity(notes.len());
        for n in &notes {
            if let Some(arr) = n.get("cards").and_then(|c| c.as_array()) {
                if let Some(first) = arr.first().and_then(|v| v.as_i64()) {
                    first_cards.push(first);
                }
            }
        }
        let card_deck: std::collections::HashMap<i64, String> = if first_cards.is_empty() {
            Default::default()
        } else {
            let v = self.call("cardsInfo", json!({ "cards": first_cards }))?;
            let arr: Vec<Value> = serde_json::from_value(v)
                .map_err(|e| AnkiError::Shape(format!("cardsInfo: {e}")))?;
            arr.into_iter()
                .filter_map(|c| {
                    let id = c.get("cardId")?.as_i64()?;
                    let deck = c.get("deckName")?.as_str()?.to_string();
                    Some((id, deck))
                })
                .collect()
        };

        let mut out = Vec::with_capacity(notes.len());
        for n in notes {
            let anki_note_id = n
                .get("noteId")
                .and_then(|v| v.as_i64())
                .ok_or_else(|| AnkiError::Shape("notesInfo missing noteId".into()))?;
            let model_name = n
                .get("modelName")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();
            let raw_tags: Vec<String> = n
                .get("tags")
                .and_then(|v| v.as_array())
                .map(|a| {
                    a.iter()
                        .filter_map(|t| t.as_str().map(String::from))
                        .collect()
                })
                .unwrap_or_default();
            let marki_id = id_from_tags(&raw_tags).unwrap_or_default();
            let hash = hash_from_tags(&raw_tags).unwrap_or_default();
            let user_tags = strip_marker(&raw_tags);
            let card_ids: Vec<i64> = n
                .get("cards")
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|v| v.as_i64()).collect())
                .unwrap_or_default();
            let deck = card_ids
                .first()
                .and_then(|id| card_deck.get(id).cloned())
                .unwrap_or_default();

            if marki_id.is_empty() {
                tracing::warn!(
                    "managed note {anki_note_id} has no marki::id:<hex> tag; skipping"
                );
                continue;
            }

            out.push(ManagedNote {
                anki_note_id,
                marki_id,
                hash,
                model_name,
                deck,
                anki_tags: user_tags,
                card_ids,
            });
        }
        Ok(out)
    }

    // ---------- note mutation ----------

    /// Add a new note. The marki id + hash are stored as tags; no custom
    /// fields. Returns the Anki-assigned noteId.
    pub fn add_note(
        &self,
        deck: &str,
        model: ModelKind,
        fields: &[(&str, &str)],
        user_tags: &[String],
        marki_id: &str,
        hash: &str,
    ) -> Result<i64, AnkiError> {
        let fields_obj: serde_json::Map<String, Value> = fields
            .iter()
            .map(|(k, v)| ((*k).to_string(), Value::String((*v).to_string())))
            .collect();
        let tags = full_tag_set(user_tags, marki_id, hash);
        let v = self.call(
            "addNote",
            json!({
                "note": {
                    "deckName": deck,
                    "modelName": model.model_name(),
                    "fields": fields_obj,
                    "tags": tags,
                    "options": { "allowDuplicate": true }
                }
            }),
        )?;
        v.as_i64()
            .ok_or_else(|| AnkiError::Shape(format!("addNote returned non-integer: {v}")))
    }

    pub fn update_note_fields(
        &self,
        anki_note_id: i64,
        fields: &[(&str, &str)],
    ) -> Result<(), AnkiError> {
        let fields_obj: serde_json::Map<String, Value> = fields
            .iter()
            .map(|(k, v)| ((*k).to_string(), Value::String((*v).to_string())))
            .collect();
        self.call(
            "updateNoteFields",
            json!({
                "note": { "id": anki_note_id, "fields": fields_obj }
            }),
        )?;
        Ok(())
    }

    /// Replace the full tag set on a note. Reapplies marker, id, and hash
    /// alongside the user tags.
    pub fn update_note_tags(
        &self,
        anki_note_id: i64,
        user_tags: &[String],
        marki_id: &str,
        hash: &str,
    ) -> Result<(), AnkiError> {
        let tags = full_tag_set(user_tags, marki_id, hash);
        self.call(
            "updateNoteTags",
            json!({ "note": anki_note_id, "tags": tags }),
        )?;
        Ok(())
    }

    pub fn change_deck(&self, card_ids: &[i64], deck: &str) -> Result<(), AnkiError> {
        if card_ids.is_empty() {
            return Ok(());
        }
        self.call("changeDeck", json!({ "cards": card_ids, "deck": deck }))?;
        Ok(())
    }

    pub fn delete_notes(&self, note_ids: &[i64]) -> Result<(), AnkiError> {
        if note_ids.is_empty() {
            return Ok(());
        }
        self.call("deleteNotes", json!({ "notes": note_ids }))?;
        Ok(())
    }

    // ---------- media ----------

    pub fn store_media_file(
        &self,
        filename: &str,
        data_base64: &str,
    ) -> Result<String, AnkiError> {
        let v = self.call(
            "storeMediaFile",
            json!({
                "filename": filename,
                "data": data_base64,
                "deleteExisting": true,
            }),
        )?;
        v.as_str()
            .map(String::from)
            .ok_or_else(|| AnkiError::Shape("storeMediaFile returned non-string".into()))
    }

    // ---------- sync ----------

    pub fn sync(&self) -> Result<(), AnkiError> {
        self.call("sync", Value::Null)?;
        Ok(())
    }
}
