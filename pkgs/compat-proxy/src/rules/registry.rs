//! Schema registry: loads canonical tool definitions from cc-schemas.toml.

use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;

use crate::wire::request::{InputSchema, Tool};

/// Raw TOML structure for the schema registry file.
#[derive(Deserialize, Debug)]
struct SchemaFile {
    tool: Vec<ToolSchemaEntry>,
}

/// A single tool definition in the registry TOML.
#[derive(Deserialize, Debug)]
struct ToolSchemaEntry {
    name: String,
    description: String,
    input_schema: InputSchemaEntry,
}

/// Input schema as defined in the registry TOML.
#[derive(Deserialize, Debug)]
struct InputSchemaEntry {
    #[serde(rename = "type")]
    schema_type: String,
    #[serde(default)]
    properties: Option<toml::Value>,
    #[serde(default)]
    required: Option<Vec<String>>,
}

/// The loaded schema registry, mapping tool names to their canonical definitions.
#[derive(Debug, Clone)]
pub struct SchemaRegistry {
    tools: HashMap<String, Tool>,
}

impl SchemaRegistry {
    /// Load the schema registry from a TOML file.
    pub fn load(path: &Path) -> Result<Self, RegistryError> {
        let content = std::fs::read_to_string(path)
            .map_err(|e| RegistryError::Io(path.display().to_string(), e))?;

        let schema_file: SchemaFile = toml::from_str(&content)
            .map_err(|e| RegistryError::Parse(path.display().to_string(), e))?;

        let mut tools = HashMap::new();
        for entry in schema_file.tool {
            let properties = entry
                .input_schema
                .properties
                .map(|v| toml_to_json_value(&v))
                .transpose()
                .map_err(|e| {
                    RegistryError::SchemaConversion(entry.name.clone(), e.to_string())
                })?;

            let tool = Tool {
                name: entry.name.clone(),
                description: Some(entry.description),
                input_schema: InputSchema {
                    schema_type: entry.input_schema.schema_type,
                    properties,
                    required: entry.input_schema.required,
                    additional_properties: None,
                },
                cache_control: None,
            };
            tools.insert(entry.name, tool);
        }

        Ok(Self { tools })
    }

    /// Look up a tool by its canonical name.
    pub fn get_tool(&self, name: &str) -> Option<&Tool> {
        self.tools.get(name)
    }

    /// List all tool names in the registry.
    pub fn tool_names(&self) -> impl Iterator<Item = &str> {
        self.tools.keys().map(|s| s.as_str())
    }
}

/// Convert a TOML value to a serde_json::Value.
///
/// The schema registry uses TOML for tool definitions, but the wire
/// format uses JSON. This converts TOML's types to their JSON equivalents.
fn toml_to_json_value(toml_val: &toml::Value) -> Result<serde_json::Value, String> {
    match toml_val {
        toml::Value::String(s) => Ok(serde_json::Value::String(s.clone())),
        toml::Value::Integer(i) => Ok(serde_json::json!(*i)),
        toml::Value::Float(f) => Ok(serde_json::json!(*f)),
        toml::Value::Boolean(b) => Ok(serde_json::Value::Bool(*b)),
        toml::Value::Array(arr) => {
            let json_arr: Result<Vec<_>, _> = arr.iter().map(toml_to_json_value).collect();
            Ok(serde_json::Value::Array(json_arr?))
        }
        toml::Value::Table(table) => {
            let mut map = serde_json::Map::new();
            for (k, v) in table {
                map.insert(k.clone(), toml_to_json_value(v)?);
            }
            Ok(serde_json::Value::Object(map))
        }
        toml::Value::Datetime(dt) => Ok(serde_json::Value::String(dt.to_string())),
    }
}

/// Errors from registry loading.
#[derive(Debug, thiserror::Error)]
pub enum RegistryError {
    #[error("failed to read registry file '{0}': {1}")]
    Io(String, std::io::Error),

    #[error("failed to parse registry file '{0}': {1}")]
    Parse(String, toml::de::Error),

    #[error("schema conversion failed for tool '{0}': {1}")]
    SchemaConversion(String, String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_toml_to_json_basic() {
        let toml_val = toml::Value::Table({
            let mut t = toml::map::Map::new();
            t.insert(
                "command".to_string(),
                toml::Value::Table({
                    let mut inner = toml::map::Map::new();
                    inner.insert(
                        "type".to_string(),
                        toml::Value::String("string".to_string()),
                    );
                    inner.insert(
                        "description".to_string(),
                        toml::Value::String("The command to execute".to_string()),
                    );
                    inner
                }),
            );
            t
        });

        let json = toml_to_json_value(&toml_val).unwrap();
        assert_eq!(json["command"]["type"], "string");
        assert_eq!(json["command"]["description"], "The command to execute");
    }
}
