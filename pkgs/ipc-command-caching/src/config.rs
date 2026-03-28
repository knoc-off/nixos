pub mod duration;
pub mod schema;

use std::path::PathBuf;

use crate::error::Error;
use schema::DaemonConfig;

/// Well-known socket path: $XDG_RUNTIME_DIR/prompt-daemon.sock
pub fn socket_path() -> PathBuf {
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR");
    PathBuf::from(runtime_dir.expect("XDG_RUNTIME_DIR must be set")).join("prompt-daemon.sock")
}

/// Resolve config file path in priority order:
/// 1. Explicit path from --config flag
/// 2. $XDG_CONFIG_HOME/prompt-daemon/config.yaml
/// 3. ~/.config/prompt-daemon/config.yaml
pub fn resolve_config_path(explicit: Option<&str>) -> Option<PathBuf> {
    if let Some(path) = explicit {
        return Some(PathBuf::from(path));
    }

    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        let path = PathBuf::from(xdg).join("prompt-daemon/config.yaml");
        if path.exists() {
            return Some(path);
        }
    }

    if let Ok(home) = std::env::var("HOME") {
        let path = PathBuf::from(home).join(".config/prompt-daemon/config.yaml");
        if path.exists() {
            return Some(path);
        }
    }

    None
}

/// Load and parse the config file.
pub fn load_config(path: &std::path::Path) -> Result<DaemonConfig, Error> {
    let contents = std::fs::read_to_string(path)?;
    let config: DaemonConfig = serde_yaml_ng::from_str(&contents)?;
    Ok(config)
}
