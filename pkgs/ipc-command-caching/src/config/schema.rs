use std::collections::HashMap;

use serde::Deserialize;

use super::duration::Duration;

#[derive(Debug, Deserialize)]
pub struct DaemonConfig {
    #[serde(default)]
    pub daemon: DaemonSection,
    #[serde(default)]
    pub defaults: DefaultsSection,
    #[serde(default)]
    pub commands: HashMap<String, CommandConfig>,
}

#[derive(Debug, Deserialize)]
pub struct DaemonSection {
    #[serde(default = "default_workers")]
    pub workers: usize,
    #[serde(default = "default_idle_timeout")]
    pub idle_timeout: Duration,
    #[serde(default = "default_log_level")]
    pub log_level: String,
}

impl Default for DaemonSection {
    fn default() -> Self {
        Self {
            workers: default_workers(),
            idle_timeout: default_idle_timeout(),
            log_level: default_log_level(),
        }
    }
}

fn default_workers() -> usize {
    4
}

fn default_idle_timeout() -> Duration {
    Duration(std::time::Duration::from_secs(60))
}

fn default_log_level() -> String {
    "info".to_string()
}

#[derive(Debug, Deserialize, Clone)]
pub struct DefaultsSection {
    #[serde(default)]
    pub shell: bool,
    #[serde(default = "default_timeout")]
    pub timeout: Duration,
    #[serde(default)]
    pub stale: StaleConfig,
}

impl Default for DefaultsSection {
    fn default() -> Self {
        Self {
            shell: false,
            timeout: default_timeout(),
            stale: StaleConfig::default(),
        }
    }
}

fn default_timeout() -> Duration {
    Duration(std::time::Duration::from_secs(10))
}

#[derive(Debug, Deserialize, Clone)]
pub struct StaleConfig {
    #[serde(default = "default_on_context_mismatch")]
    pub on_context_mismatch: String,
    #[serde(default = "default_on_expired")]
    pub on_expired: String,
    #[serde(default)]
    pub on_empty: String,
    #[serde(default)]
    pub on_error: String,
}

impl Default for StaleConfig {
    fn default() -> Self {
        Self {
            on_context_mismatch: default_on_context_mismatch(),
            on_expired: default_on_expired(),
            on_empty: String::new(),
            on_error: String::new(),
        }
    }
}

fn default_on_context_mismatch() -> String {
    "\u{2026}".to_string()
}

fn default_on_expired() -> String {
    "?".to_string()
}

#[derive(Debug, Deserialize, Clone)]
pub struct CommandConfig {
    pub run: String,
    #[serde(default)]
    pub shell: Option<bool>,
    #[serde(default)]
    pub env: Vec<String>,
    #[serde(default)]
    pub exec_in_cwd: bool,
    #[serde(default)]
    pub interval: Option<Duration>,
    #[serde(default)]
    pub max_age: Option<Duration>,
    #[serde(default)]
    pub timeout: Option<Duration>,
    #[serde(default)]
    pub stale: Option<StaleConfig>,
}

/// The magic env var name for the client's working directory.
/// Always sent in protocol phase 1; never requested in phase 2.
pub const ENV_CWD: &str = "CWD";

impl CommandConfig {
    /// Env var names to request from the client (phase 2).
    /// Excludes CWD since it's always provided in phase 1.
    pub fn client_env_vars(&self) -> Vec<String> {
        self.env
            .iter()
            .filter(|v| v.as_str() != ENV_CWD)
            .cloned()
            .collect()
    }

    /// Whether CWD participates in this command's cache key.
    pub fn uses_cwd(&self) -> bool {
        self.env.iter().any(|v| v.as_str() == ENV_CWD)
    }

    pub fn effective_shell(&self, defaults: &DefaultsSection) -> bool {
        self.shell.unwrap_or(defaults.shell)
    }

    pub fn effective_timeout(&self, defaults: &DefaultsSection) -> std::time::Duration {
        self.timeout
            .as_ref()
            .unwrap_or(&defaults.timeout)
            .0
    }

    pub fn effective_stale<'a>(&'a self, defaults: &'a DefaultsSection) -> &'a StaleConfig {
        self.stale.as_ref().unwrap_or(&defaults.stale)
    }
}
