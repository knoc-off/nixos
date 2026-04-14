//! TOML serde structs for client rule files.
//!
//! These are the raw deserialized forms. After validation they are
//! converted into `RuleSet` which pre-resolves all references.

use serde::Deserialize;

/// Top-level rule file structure.
#[derive(Deserialize, Debug, Clone)]
pub struct RulesFile {
    pub meta: MetaConfig,
    #[serde(default)]
    pub system_prompt: Option<SystemPromptConfig>,
    #[serde(default)]
    pub tools: Option<ToolsConfig>,
    #[serde(default)]
    pub properties: Option<PropertiesConfig>,
    #[serde(default)]
    pub headers: Option<HeadersConfig>,
    #[serde(default)]
    pub billing: Option<BillingConfig>,
}

/// Metadata about the client and target version.
#[derive(Deserialize, Debug, Clone)]
pub struct MetaConfig {
    pub client_name: String,
    pub target_cc_version: String,
}

/// System prompt detection and replacement configuration.
#[derive(Deserialize, Debug, Clone)]
pub struct SystemPromptConfig {
    /// Substring to detect in the system prompt.
    pub detect: Option<String>,
    /// Path to replacement file, relative to the rules file.
    pub replace_with_file: Option<String>,
    /// Text replacements applied after wholesale replacement.
    #[serde(default)]
    pub text_replacements: Vec<TextReplacementConfig>,
}

/// A single find/replace pair for text blocks.
#[derive(Deserialize, Debug, Clone)]
pub struct TextReplacementConfig {
    pub find: String,
    pub replace: String,
}

/// Tool mapping configuration.
#[derive(Deserialize, Debug, Clone)]
pub struct ToolsConfig {
    /// Policy for tools with no rule: "error", "drop", or "passthrough".
    #[serde(default)]
    pub unmapped_policy: UnmappedPolicy,
    /// Tool renames: client name → canonical schema name.
    #[serde(default)]
    pub rename: Vec<ToolRenameConfig>,
    /// Tools to drop silently.
    #[serde(default)]
    pub drop: Vec<ToolDropConfig>,
}

/// Policy for unmapped tools.
#[derive(Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum UnmappedPolicy {
    Error,
    Drop,
    Passthrough,
}

impl Default for UnmappedPolicy {
    fn default() -> Self {
        Self::Error
    }
}

/// A tool rename rule.
#[derive(Deserialize, Debug, Clone)]
pub struct ToolRenameConfig {
    /// The client's tool name.
    pub from: String,
    /// Name in the schema registry.
    pub to_schema: String,
}

/// A tool to drop.
#[derive(Deserialize, Debug, Clone)]
pub struct ToolDropConfig {
    pub name: String,
}

/// Property rename configuration.
#[derive(Deserialize, Debug, Clone)]
pub struct PropertiesConfig {
    #[serde(default)]
    pub rename: Vec<PropertyRenameConfig>,
}

/// A bidirectional property rename.
#[derive(Deserialize, Debug, Clone)]
pub struct PropertyRenameConfig {
    pub from: String,
    pub to: String,
}

/// Header injection configuration.
#[derive(Deserialize, Debug, Clone)]
pub struct HeadersConfig {
    #[serde(default)]
    pub inject: Vec<HeaderInjectConfig>,
}

/// A single header to inject, with optional template variables.
#[derive(Deserialize, Debug, Clone)]
pub struct HeaderInjectConfig {
    pub name: String,
    pub value: String,
}

/// Billing block injection configuration.
#[derive(Deserialize, Debug, Clone)]
pub struct BillingConfig {
    #[serde(default)]
    pub inject_block: bool,
    pub cc_version: Option<String>,
    /// SHA256 hash salt for billing fingerprint (optional, has default).
    pub hash_salt: Option<String>,
    /// Character indices from first user message for fingerprint (optional, has default).
    pub hash_indices: Option<Vec<usize>>,
}
