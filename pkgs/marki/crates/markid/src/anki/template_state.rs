//! Template ordering persistence.
//!
//! Tracks the `(model_name, card_name) → ordinal` mapping to enforce
//! the **append-only** rule: Anki identifies cards by `(note_id,
//! template_ordinal)`, so reordering or removing templates would
//! corrupt existing reviews.
//!
//! State is persisted to `<config_dir>/model_state.json`.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

/// Per-model state: the ordered list of card names (by ordinal).
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ModelState {
    pub card_names: Vec<String>,
}

/// All model states, keyed by model name.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct TemplateState {
    pub models: HashMap<String, ModelState>,
}

/// Error when a model's card_names violate the append-only rule.
#[derive(Debug, Clone, thiserror::Error)]
pub enum OrderingError {
    #[error("model '{model}': card_names reordered or removed (was {old:?}, now {new:?})")]
    NonAppend {
        model: String,
        old: Vec<String>,
        new: Vec<String>,
    },
}

impl TemplateState {
    /// Load from disk. Returns a fresh empty state if the file doesn't
    /// exist or can't be parsed.
    pub fn load(path: &Path) -> Self {
        match std::fs::read_to_string(path) {
            Ok(data) => match serde_json::from_str(&data) {
                Ok(state) => state,
                Err(e) => {
                    tracing::warn!("corrupt template state at {}: {e} — starting fresh", path.display());
                    Self::default()
                }
            },
            Err(_) => Self::default(),
        }
    }

    /// Save to disk.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        let data = serde_json::to_string_pretty(self)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, data)
    }

    /// Validate that a model's new card_names are a valid append to the
    /// previously-stored ordering. Returns `Ok(true)` if new names were
    /// appended, `Ok(false)` if unchanged.
    ///
    /// Updates the stored state on success.
    pub fn validate_and_update(
        &mut self,
        model: &str,
        new_card_names: &[String],
    ) -> Result<bool, OrderingError> {
        let entry = self.models.entry(model.to_string()).or_default();
        let old = &entry.card_names;

        if old.is_empty() {
            // First time seeing this model — accept whatever it declares.
            entry.card_names = new_card_names.to_vec();
            return Ok(true);
        }

        // Check: old must be a prefix of new (append-only).
        if new_card_names.len() < old.len() {
            return Err(OrderingError::NonAppend {
                model: model.to_string(),
                old: old.clone(),
                new: new_card_names.to_vec(),
            });
        }
        for (i, old_name) in old.iter().enumerate() {
            if new_card_names.get(i) != Some(old_name) {
                return Err(OrderingError::NonAppend {
                    model: model.to_string(),
                    old: old.clone(),
                    new: new_card_names.to_vec(),
                });
            }
        }

        if new_card_names.len() > old.len() {
            // Appended new card names — update and signal.
            entry.card_names = new_card_names.to_vec();
            Ok(true)
        } else {
            // Unchanged.
            Ok(false)
        }
    }

    /// Path for the state file given a config directory.
    pub fn default_path(config_dir: &Path) -> PathBuf {
        config_dir.join("model_state.json")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_registration_always_succeeds() {
        let mut state = TemplateState::default();
        let result = state.validate_and_update(
            "geo",
            &["Locate".into(), "Identify".into()],
        );
        assert!(result.is_ok());
        assert!(result.unwrap()); // true = new
    }

    #[test]
    fn unchanged_returns_false() {
        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into(), "Identify".into()]).unwrap();
        let result = state.validate_and_update(
            "geo",
            &["Locate".into(), "Identify".into()],
        );
        assert_eq!(result.unwrap(), false);
    }

    #[test]
    fn append_succeeds() {
        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into()]).unwrap();
        let result = state.validate_and_update(
            "geo",
            &["Locate".into(), "Identify".into()],
        );
        assert!(result.is_ok());
        assert!(result.unwrap()); // true = appended
        assert_eq!(state.models["geo"].card_names.len(), 2);
    }

    #[test]
    fn reorder_fails() {
        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into(), "Identify".into()]).unwrap();
        let result = state.validate_and_update(
            "geo",
            &["Identify".into(), "Locate".into()],
        );
        assert!(result.is_err());
    }

    #[test]
    fn removal_fails() {
        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into(), "Identify".into()]).unwrap();
        let result = state.validate_and_update(
            "geo",
            &["Locate".into()],
        );
        assert!(result.is_err());
    }

    #[test]
    fn different_models_are_independent() {
        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into()]).unwrap();
        state.validate_and_update("lang", &["Translate".into()]).unwrap();
        assert_eq!(state.models.len(), 2);
    }

    #[test]
    fn save_and_load_round_trip() {
        let dir = std::env::temp_dir().join("marki-test-template-state");
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join("state.json");

        let mut state = TemplateState::default();
        state.validate_and_update("geo", &["Locate".into(), "Identify".into()]).unwrap();
        state.save(&path).unwrap();

        let loaded = TemplateState::load(&path);
        assert_eq!(loaded.models["geo"].card_names, vec!["Locate", "Identify"]);

        let _ = std::fs::remove_dir_all(&dir);
    }
}
