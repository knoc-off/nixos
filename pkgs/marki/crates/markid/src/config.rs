//! Configuration loading.
//!
//! Config lives at `~/.config/markid/config.toml` by default; overridable
//! via `--config` and/or `$MARKID_CONFIG`.

use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::time::Duration;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Directory of `.md` cards to sync. May or may not be a git repo;
    /// markid itself never shells out to git.
    pub cards_dir: PathBuf,

    /// AnkiConnect URL. Default: `http://127.0.0.1:8765`.
    #[serde(default = "default_endpoint")]
    pub anki_endpoint: String,

    /// Seconds between reconciliation heartbeat passes in watch mode.
    #[serde(default = "default_sync_interval", with = "duration_secs")]
    pub sync_interval: Duration,

    /// Debounce window for inotify events, in milliseconds.
    #[serde(default = "default_debounce_ms")]
    pub debounce_ms: u64,

    /// Whether to call AnkiConnect `sync` before and after each cycle to
    /// round-trip changes via AnkiWeb.
    #[serde(default = "default_ankiweb_sync")]
    pub ankiweb_sync: bool,
}

fn default_endpoint() -> String {
    "http://127.0.0.1:8765".into()
}
fn default_sync_interval() -> Duration {
    Duration::from_secs(300)
}
fn default_debounce_ms() -> u64 {
    250
}
fn default_ankiweb_sync() -> bool {
    true
}

mod duration_secs {
    use serde::Deserialize;
    use std::time::Duration;

    pub fn deserialize<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Duration, D::Error> {
        // Accept either bare u64 seconds or a humantime-ish string like "5m".
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Repr {
            Secs(u64),
            Str(String),
        }
        match Repr::deserialize(d)? {
            Repr::Secs(n) => Ok(Duration::from_secs(n)),
            Repr::Str(s) => parse_duration(&s).map_err(serde::de::Error::custom),
        }
    }

    fn parse_duration(s: &str) -> Result<Duration, String> {
        let s = s.trim();
        let split = s
            .find(|c: char| c.is_alphabetic())
            .unwrap_or(s.len());
        let (num, unit) = s.split_at(split);
        let n: u64 = num.trim().parse().map_err(|_| format!("bad duration: {s}"))?;
        let mul = match unit.trim() {
            "" | "s" => 1,
            "m" => 60,
            "h" => 3600,
            "d" => 86400,
            other => return Err(format!("unknown unit: {other}")),
        };
        Ok(Duration::from_secs(n * mul))
    }
}

impl Config {
    pub fn default_path() -> Option<PathBuf> {
        dirs::config_dir().map(|c| c.join("markid").join("config.toml"))
    }

    pub fn load_from(path: &Path) -> anyhow::Result<Self> {
        let raw = std::fs::read_to_string(path)?;
        Ok(toml::from_str(&raw)?)
    }
}
