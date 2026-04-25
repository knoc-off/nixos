pub mod apply_request;
pub mod apply_response;
pub mod apply_sse;
pub mod registry;
pub mod schema;
pub mod validate;

use std::collections::HashMap;

use crate::wire::request::InputSchema;

pub use apply_request::apply_request_rules;
pub use apply_response::apply_response_rules;
pub use apply_sse::apply_sse_event_rules;
pub use registry::SchemaRegistry;
pub use schema::{RulesFile, UnmappedPolicy};
pub use validate::validate_rules;

/// A validated, ready-to-use rule set.
///
/// Pre-resolves all schema references, reads replacement files,
/// renders header templates. Rule application functions take `&RuleSet`.
#[derive(Debug, Clone)]
pub struct RuleSet {
    /// Client name from the rule file metadata.
    pub client_name: String,

    /// Target runtime version.
    pub cc_version: String,

    /// System prompt detection substring.
    pub system_prompt_detect: Option<String>,

    /// Replacement system prompt text (pre-read from file).
    pub system_prompt_replacement: Option<String>,

    /// Text to append to the system prompt (pre-read from file).
    /// Applied after replacement and text replacements.
    pub system_prompt_append: Option<String>,

    /// Text replacements applied after system prompt replacement.
    pub text_replacements: Vec<TextReplacement>,

    /// Tool rename mappings: client name → (canonical name, resolved Tool definition).
    pub tool_renames: HashMap<String, ResolvedToolRename>,

    /// Tool names to drop (remove from request).
    pub tool_drops: std::collections::HashSet<String>,

    /// Policy for tools that have no mapping rule.
    pub unmapped_policy: UnmappedPolicy,

    /// Bidirectional property renames: (from, to).
    /// Applied forward on requests, reversed on responses.
    pub property_renames: Vec<PropertyRename>,

    /// Headers to inject on the upstream request.
    pub headers: Vec<ResolvedHeader>,

    /// Whether to inject the billing block into the system prompt.
    pub inject_billing_block: bool,

    /// Billing block runtime version (may differ from meta cc_version).
    pub billing_cc_version: Option<String>,

    /// SHA256 hash salt for billing fingerprint (from real CC).
    pub billing_hash_salt: String,

    /// Character indices from first user message for fingerprint.
    pub billing_hash_indices: Vec<usize>,
}

/// A resolved tool rename: the canonical name, optional description
/// override, and optional schema override.
///
/// When `schema_override` is `None`, the client's original `input_schema`
/// is preserved — this is the default and recommended mode. Schema
/// overrides are only needed when a client sends an incorrect schema.
#[derive(Debug, Clone)]
pub struct ResolvedToolRename {
    /// The canonical tool name (e.g., "Bash").
    pub canonical_name: String,

    /// Description override. When `Some`, replaces the client's description.
    pub description: Option<String>,

    /// Schema override. When `Some`, replaces the client's input_schema
    /// (with client's `required`/`additionalProperties` merged as fallback).
    /// When `None`, the client's schema is preserved intact.
    pub schema_override: Option<InputSchema>,
}

/// A text find/replace pair.
#[derive(Debug, Clone)]
pub struct TextReplacement {
    pub find: String,
    pub replace: String,
}

/// A bidirectional property rename.
#[derive(Debug, Clone)]
pub struct PropertyRename {
    pub from: String,
    pub to: String,
}

/// A header with template variables already resolved.
#[derive(Debug, Clone)]
pub struct ResolvedHeader {
    pub name: String,
    pub value: String,
}

impl RuleSet {
    /// Look up the canonical name for a client tool name.
    /// Returns None if the tool is not in the rename map.
    pub fn canonical_name(&self, client_name: &str) -> Option<&str> {
        self.tool_renames
            .get(client_name)
            .map(|r| r.canonical_name.as_str())
    }

    /// Look up the client name for a canonical tool name (reverse lookup).
    pub fn client_name_for(&self, canonical_name: &str) -> Option<&str> {
        self.tool_renames
            .iter()
            .find(|(_, v)| v.canonical_name == canonical_name)
            .map(|(k, _)| k.as_str())
    }

    /// Build a reverse property rename map (to → from).
    pub fn reverse_property_renames(&self) -> Vec<PropertyRename> {
        self.property_renames
            .iter()
            .map(|r| PropertyRename {
                from: r.to.clone(),
                to: r.from.clone(),
            })
            .collect()
    }
}

/// Errors that can occur during rule application.
#[derive(Debug, thiserror::Error)]
pub enum RuleError {
    #[error("unmapped tool: {0} (policy is 'error')")]
    UnmappedTool(String),

    #[error("tool rename failed for '{0}': schema not found")]
    SchemaNotFound(String),

    #[error("property rename failed: {0}")]
    PropertyRenameFailed(String),

    #[error("system prompt replacement failed: {0}")]
    SystemPromptFailed(String),

    #[error("SSE event translation failed: {0}")]
    SseTranslationFailed(String),

    #[error("JSON parse error during property rename: {0}")]
    JsonParse(#[from] serde_json::Error),
}
