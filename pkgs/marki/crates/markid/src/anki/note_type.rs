//! Custom note type management.
//!
//! Ensures that Anki has the right note type (model) for each Rhai
//! model script. A model named `geographic-location` with
//! `card_names() = ["Locate", "Identify"]` becomes an Anki note type
//! called `marki:geographic-location` with fields:
//!
//!   `LocateFront`, `LocateBack`, `IdentifyFront`, `IdentifyBack`
//!
//! And templates:
//!   - "Locate": front = `{{LocateFront}}`, back = `{{LocateBack}}`
//!   - "Identify": front = `{{IdentifyFront}}`, back = `{{IdentifyBack}}`
//!
//! Templates use pass-through — the Rhai script already produced final
//! HTML, so Anki just displays it.

use super::client::{AnkiConnect, AnkiError};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::path::Path;

/// Prefix for all marki-managed note type names in Anki.
pub const MODEL_PREFIX: &str = "marki:";

/// Specification for a custom note type derived from a model script.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoteTypeSpec {
    /// Anki model name (e.g., `"marki:geographic-location"`).
    pub model_name: String,
    /// Card names from `card_names()` in order. Each produces two fields
    /// (`{Name}Front`, `{Name}Back`) and one template.
    pub card_names: Vec<String>,
}

impl NoteTypeSpec {
    /// Create a spec from a model name and its declared card names.
    pub fn new(model_name: &str, card_names: Vec<String>) -> Self {
        Self {
            model_name: format!("{MODEL_PREFIX}{model_name}"),
            card_names,
        }
    }

    /// Field names for this note type (in order).
    pub fn field_names(&self) -> Vec<String> {
        let mut fields = Vec::with_capacity(self.card_names.len() * 2);
        for name in &self.card_names {
            fields.push(format!("{name}Front"));
            fields.push(format!("{name}Back"));
        }
        fields
    }

    /// Anki model name.
    pub fn anki_model_name(&self) -> &str {
        &self.model_name
    }
}

/// Ensure the note type exists in Anki and has the correct fields and
/// templates. Creates it if missing; validates field list if it already
/// exists.
///
/// Returns `Ok(true)` if the model was created, `Ok(false)` if it
/// already existed with the correct fields.
pub fn ensure_note_type(
    anki: &AnkiConnect,
    spec: &NoteTypeSpec,
) -> Result<bool, AnkiError> {
    // Check if the model already exists.
    let existing = anki.call("modelNames", Value::Null)?;
    let model_names: Vec<String> = serde_json::from_value(existing)
        .map_err(|e| AnkiError::Shape(format!("modelNames: {e}")))?;

    if model_names.contains(&spec.model_name) {
        // Model exists — verify fields match.
        let fields = anki.call("modelFieldNames", json!({ "modelName": spec.model_name }))?;
        let existing_fields: Vec<String> = serde_json::from_value(fields)
            .map_err(|e| AnkiError::Shape(format!("modelFieldNames: {e}")))?;
        let expected_fields = spec.field_names();
        if existing_fields != expected_fields {
            // Fields mismatch — this could mean card_names were reordered
            // or modified. Log but don't crash; the template ordering
            // validator will catch this.
            tracing::warn!(
                model = %spec.model_name,
                expected = ?expected_fields,
                actual = ?existing_fields,
                "note type field mismatch — templates may need manual fix"
            );
        }
        return Ok(false);
    }

    // Create the model.
    let fields = spec.field_names();

    let templates: Vec<Value> = spec.card_names.iter()
        .map(|name| {
            let front_field = format!("{name}Front");
            let back_field = format!("{name}Back");
            json!({
                "Name": name,
                "Front": format!("{{{{{front_field}}}}}"),
                "Back": format!("{{{{{back_field}}}}}"),
            })
        })
        .collect();

    anki.call(
        "createModel",
        json!({
            "modelName": spec.model_name,
            "inOrderFields": fields,
            "cardTemplates": templates,
        }),
    )?;

    tracing::info!(model = %spec.model_name, cards = ?spec.card_names, "created Anki note type");
    Ok(true)
}

/// Push CSS styling for a model. Reads from `models/<name>.css` if it
/// exists; otherwise uses a minimal default.
pub fn push_model_styling(
    anki: &AnkiConnect,
    spec: &NoteTypeSpec,
    models_dir: &Path,
) -> Result<(), AnkiError> {
    let model_short_name = spec.model_name
        .strip_prefix(MODEL_PREFIX)
        .unwrap_or(&spec.model_name);
    let css_path = models_dir.join(format!("{model_short_name}.css"));
    let css = if css_path.exists() {
        std::fs::read_to_string(&css_path).unwrap_or_default()
    } else {
        DEFAULT_CSS.to_string()
    };

    anki.call(
        "updateModelStyling",
        json!({
            "model": {
                "name": spec.model_name,
                "css": css,
            }
        }),
    )?;
    Ok(())
}

/// Minimal default CSS for marki note types.
const DEFAULT_CSS: &str = r#"
.card {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 16px;
    text-align: center;
    color: #1a1a1a;
    background: #fafafa;
    padding: 1em;
}
img {
    max-width: 100%;
    height: auto;
}
"#;

/// Build the field values map from a model output (HashMap<String, String>)
/// for use with `addNote`/`updateNoteFields`. Maps model output keys to
/// the note type's field names. Missing fields get empty strings (which
/// suppresses that card template in Anki).
pub fn build_field_values(
    spec: &NoteTypeSpec,
    model_output: &HashMap<String, String>,
) -> Vec<(String, String)> {
    let mut fields = Vec::new();
    for field_name in spec.field_names() {
        let value = model_output
            .get(&field_name)
            .cloned()
            .unwrap_or_default();
        fields.push((field_name, value));
    }
    fields
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn note_type_spec_field_names() {
        let spec = NoteTypeSpec::new("geo", vec!["Locate".into(), "Identify".into()]);
        assert_eq!(spec.model_name, "marki:geo");
        assert_eq!(
            spec.field_names(),
            vec!["LocateFront", "LocateBack", "IdentifyFront", "IdentifyBack"]
        );
    }

    #[test]
    fn note_type_spec_single_card() {
        let spec = NoteTypeSpec::new("basic", vec!["Card".into()]);
        assert_eq!(spec.field_names(), vec!["CardFront", "CardBack"]);
    }

    #[test]
    fn build_field_values_fills_missing() {
        let spec = NoteTypeSpec::new("geo", vec!["Locate".into(), "Identify".into()]);
        let mut output = HashMap::new();
        output.insert("LocateFront".into(), "<p>Where?</p>".into());
        output.insert("LocateBack".into(), "<p>Here!</p>".into());
        // IdentifyFront and IdentifyBack are missing → empty

        let fields = build_field_values(&spec, &output);
        assert_eq!(fields.len(), 4);
        assert_eq!(fields[0], ("LocateFront".into(), "<p>Where?</p>".into()));
        assert_eq!(fields[1], ("LocateBack".into(), "<p>Here!</p>".into()));
        assert_eq!(fields[2], ("IdentifyFront".into(), String::new()));
        assert_eq!(fields[3], ("IdentifyBack".into(), String::new()));
    }

    #[test]
    fn build_field_values_ignores_extra_keys() {
        let spec = NoteTypeSpec::new("basic", vec!["Card".into()]);
        let mut output = HashMap::new();
        output.insert("CardFront".into(), "Q".into());
        output.insert("CardBack".into(), "A".into());
        output.insert("ExtraStuff".into(), "ignored".into());

        let fields = build_field_values(&spec, &output);
        assert_eq!(fields.len(), 2);
    }
}
