//! Startup validation for rule files.
//!
//! Validates a parsed RulesFile against a SchemaRegistry and produces
//! either a ready-to-use RuleSet or a list of ALL validation errors
//! (not fail-fast — typos in a TOML file should never reach runtime).

use std::collections::HashSet;
use std::path::Path;

use crate::rules::{
    PropertyRename, ResolvedHeader, ResolvedToolRename, RuleSet, TextReplacement,
    UnknownFieldRule,
};

use super::registry::SchemaRegistry;
use super::schema::{RulesFile, UnknownFieldAction, UnmappedPolicy};

/// Validate a rules file against the schema registry.
///
/// `rules_dir` is the directory containing the rules file, used to
/// resolve relative paths (e.g., `replace_with_file`).
pub fn validate_rules(
    rules_file: &RulesFile,
    registry: &SchemaRegistry,
    rules_dir: &Path,
) -> Result<RuleSet, Vec<ValidationError>> {
    let mut errors = Vec::new();

    let client_name = rules_file.meta.client_name.clone();
    let cc_version = rules_file.meta.target_cc_version.clone();

    // -- System prompt validation --
    let mut system_prompt_detect = None;
    let mut system_prompt_replacement = None;
    let mut system_prompt_append = None;
    let mut text_replacements = Vec::new();

    if let Some(sp) = &rules_file.system_prompt {
        system_prompt_detect = sp.detect.clone();

        if let Some(ref path) = sp.replace_with_file {
            let full_path = rules_dir.join(path);
            match std::fs::read_to_string(&full_path) {
                Ok(content) => system_prompt_replacement = Some(content),
                Err(e) => errors.push(ValidationError::FileNotFound(
                    full_path.display().to_string(),
                    e.to_string(),
                )),
            }
        }

        if let Some(ref path) = sp.append_file {
            let full_path = rules_dir.join(path);
            match std::fs::read_to_string(&full_path) {
                Ok(content) => system_prompt_append = Some(content),
                Err(e) => errors.push(ValidationError::FileNotFound(
                    full_path.display().to_string(),
                    e.to_string(),
                )),
            }
        }

        for tr in &sp.text_replacements {
            text_replacements.push(TextReplacement {
                find: tr.find.clone(),
                replace: tr.replace.clone(),
            });
        }
    }

    // -- Tool validation --
    let mut tool_renames = std::collections::HashMap::new();
    let mut tool_drops = HashSet::new();
    let mut unmapped_policy = UnmappedPolicy::Error;
    let mut seen_froms = HashSet::new();

    if let Some(tools) = &rules_file.tools {
        unmapped_policy = tools.unmapped_policy.clone();

        // Check for collisions and validate schema references
        for rename in &tools.rename {
            // Duplicate from check
            if !seen_froms.insert(rename.from.clone()) {
                errors.push(ValidationError::DuplicateFrom(rename.from.clone()));
            }

            // Schema reference check
            match registry.get_tool(&rename.to_schema) {
                Some(reg_tool) => {
                    tool_renames.insert(
                        rename.from.clone(),
                        ResolvedToolRename {
                            canonical_name: rename.to_schema.clone(),
                            description: reg_tool.description.clone(),
                            schema_override: reg_tool.input_schema.clone(),
                        },
                    );
                }
                None => {
                    errors.push(ValidationError::SchemaNotFound(
                        rename.to_schema.clone(),
                        rename.from.clone(),
                    ));
                }
            }
        }

        for drop in &tools.drop {
            // Check rename+drop overlap
            if seen_froms.contains(&drop.name) {
                errors.push(ValidationError::RenameDropOverlap(drop.name.clone()));
            }
            tool_drops.insert(drop.name.clone());
        }
    }

    // -- Property validation --
    let mut property_renames = Vec::new();
    if let Some(props) = &rules_file.properties {
        let mut seen_prop_froms = HashSet::new();
        for rename in &props.rename {
            if !seen_prop_froms.insert(rename.from.clone()) {
                errors.push(ValidationError::DuplicatePropertyFrom(
                    rename.from.clone(),
                ));
            }
            property_renames.push(PropertyRename {
                from: rename.from.clone(),
                to: rename.to.clone(),
            });
        }
    }

    // -- Header validation --
    let mut headers = Vec::new();
    if let Some(hdr) = &rules_file.headers {
        for inject in &hdr.inject {
            // Resolve template variables in header values
            let resolved_value = inject
                .value
                .replace("{cc_version}", &cc_version);

            // Check for unresolved template variables
            if resolved_value.contains('{') && resolved_value.contains('}') {
                // Simple check — find {word} patterns that weren't resolved
                let mut remaining = resolved_value.as_str();
                while let Some(start) = remaining.find('{') {
                    if let Some(end) = remaining[start..].find('}') {
                        let var = &remaining[start..start + end + 1];
                        // Only warn if it looks like a template var (no spaces)
                        if !var.contains(' ') && var.len() > 2 {
                            errors.push(ValidationError::UnresolvedTemplateVar(
                                inject.name.clone(),
                                var.to_string(),
                            ));
                        }
                        remaining = &remaining[start + end + 1..];
                    } else {
                        break;
                    }
                }
            }

            headers.push(ResolvedHeader {
                name: inject.name.clone(),
                value: resolved_value,
            });
        }
    }

    // -- Billing validation --
    let mut inject_billing_block = false;
    let mut billing_cc_version = None;
    let mut billing_hash_salt = crate::config::BILLING_HASH_SALT.to_string();
    let mut billing_hash_indices = crate::config::BILLING_HASH_INDICES.to_vec();
    if let Some(billing) = &rules_file.billing {
        inject_billing_block = billing.inject_block;
        billing_cc_version = billing.cc_version.clone();
        if let Some(ref salt) = billing.hash_salt {
            billing_hash_salt = salt.clone();
        }
        if let Some(ref indices) = billing.hash_indices {
            billing_hash_indices = indices.clone();
        }
    }

    // Unknown field rules
    let mut unknown_field_rules = std::collections::HashMap::new();
    if let Some(uf) = &rules_file.unknown_fields {
        let mut seen = HashSet::new();
        for rule in &uf.rules {
            if !seen.insert(rule.name.clone()) {
                errors.push(ValidationError::DuplicateUnknownField(rule.name.clone()));
                continue;
            }
            let resolved = match rule.action {
                UnknownFieldAction::Strip => UnknownFieldRule::Strip,
                UnknownFieldAction::Keep => UnknownFieldRule::Keep,
                UnknownFieldAction::Rename => match &rule.rename_to {
                    Some(target) => UnknownFieldRule::Rename(target.clone()),
                    None => {
                        errors.push(ValidationError::RenameMissingTarget(rule.name.clone()));
                        continue;
                    }
                },
            };
            unknown_field_rules.insert(rule.name.clone(), resolved);
        }
    }

    if errors.is_empty() {
        Ok(RuleSet {
            client_name,
            cc_version,
            system_prompt_detect,
            system_prompt_replacement,
            system_prompt_append,
            text_replacements,
            tool_renames,
            tool_drops,
            unmapped_policy,
            property_renames,
            headers,
            inject_billing_block,
            billing_cc_version,
            billing_hash_salt,
            billing_hash_indices,
            unknown_field_rules,
        })
    } else {
        Err(errors)
    }
}

/// Validation errors — all collected before reporting.
#[derive(Debug, thiserror::Error)]
pub enum ValidationError {
    #[error("schema '{0}' not found in registry (referenced by tool rename from '{1}')")]
    SchemaNotFound(String, String),

    #[error("duplicate 'from' value in tool renames: '{0}'")]
    DuplicateFrom(String),

    #[error("tool '{0}' appears in both rename and drop lists")]
    RenameDropOverlap(String),

    #[error("replacement file not found: '{0}' ({1})")]
    FileNotFound(String, String),

    #[error("unresolved template variable in header '{0}': {1}")]
    UnresolvedTemplateVar(String, String),

    #[error("duplicate 'from' value in property renames: '{0}'")]
    DuplicatePropertyFrom(String),

    #[error("duplicate unknown_fields rule for '{0}'")]
    DuplicateUnknownField(String),

    #[error("unknown_fields rule for '{0}' uses action='rename' but no 'rename_to' provided")]
    RenameMissingTarget(String),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rules::schema::*;

    fn empty_registry() -> SchemaRegistry {
        let path = std::env::temp_dir().join(format!(
            "compat-proxy-schemas-{:?}.toml",
            std::thread::current().id(),
        ));
        std::fs::write(
            &path,
            "[[tool]]\nname = \"Bash\"\ndescription = \"test\"\n",
        )
        .unwrap();
        SchemaRegistry::load(&path).unwrap()
    }

    #[test]
    fn test_duplicate_from_detected() {
        let registry = empty_registry();
        let rules_file = RulesFile {
            meta: MetaConfig {
                client_name: "test".into(),
                target_cc_version: "1.0".into(),
            },
            system_prompt: None,
            tools: Some(ToolsConfig {
                unmapped_policy: UnmappedPolicy::Error,
                rename: vec![
                    ToolRenameConfig {
                        from: "mcp_bash".into(),
                        to_schema: "Bash".into(),
                    },
                    ToolRenameConfig {
                        from: "mcp_bash".into(),
                        to_schema: "Bash".into(),
                    },
                ],
                drop: vec![],
            }),
            properties: None,
            headers: None,
            billing: None,
            unknown_fields: None,
        };

        let result = validate_rules(&rules_file, &registry, Path::new("/tmp"));
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .iter()
            .any(|e| matches!(e, ValidationError::DuplicateFrom(_))));
    }

    #[test]
    fn test_schema_not_found_detected() {
        let registry = empty_registry();
        let rules_file = RulesFile {
            meta: MetaConfig {
                client_name: "test".into(),
                target_cc_version: "1.0".into(),
            },
            system_prompt: None,
            tools: Some(ToolsConfig {
                unmapped_policy: UnmappedPolicy::Error,
                rename: vec![ToolRenameConfig {
                    from: "mcp_read".into(),
                    to_schema: "NonExistent".into(),
                }],
                drop: vec![],
            }),
            properties: None,
            headers: None,
            billing: None,
            unknown_fields: None,
        };

        let result = validate_rules(&rules_file, &registry, Path::new("/tmp"));
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .iter()
            .any(|e| matches!(e, ValidationError::SchemaNotFound(_, _))));
    }

    #[test]
    fn test_rename_drop_overlap_detected() {
        let registry = empty_registry();
        let rules_file = RulesFile {
            meta: MetaConfig {
                client_name: "test".into(),
                target_cc_version: "1.0".into(),
            },
            system_prompt: None,
            tools: Some(ToolsConfig {
                unmapped_policy: UnmappedPolicy::Error,
                rename: vec![ToolRenameConfig {
                    from: "mcp_bash".into(),
                    to_schema: "Bash".into(),
                }],
                drop: vec![ToolDropConfig {
                    name: "mcp_bash".into(),
                }],
            }),
            properties: None,
            headers: None,
            billing: None,
            unknown_fields: None,
        };

        let result = validate_rules(&rules_file, &registry, Path::new("/tmp"));
        assert!(result.is_err());
        let errors = result.unwrap_err();
        assert!(errors
            .iter()
            .any(|e| matches!(e, ValidationError::RenameDropOverlap(_))));
    }
}
