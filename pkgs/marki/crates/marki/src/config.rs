//! Configuration loading and project discovery.
//!
//! `marki` is repo-centric: it walks up from the current directory to
//! find a hidden `.marki/` directory (git-style), and treats the
//! directory that contains it as the *project root*. Cards are the `.md`
//! files in the project root; everything that defines and renders them —
//! `config.toml`, `models/`, `lib/`, and `media/` — lives inside `.marki/`,
//! so a flashcard repo is fully self-contained. The collection it writes to
//! is a `.anki2` file (with a sibling `media/` dir and `media.db`) named by
//! the `collection` key.
//!
//! Config precedence: `--config` / `$MARKI_CONFIG` win; otherwise the
//! nearest `.marki/config.toml`; otherwise the legacy global
//! `$XDG_CONFIG_HOME/marki/config.toml`. A `.marki/` with no config is
//! valid — pure defaults apply.
//!
//! String/path values support shell-style environment interpolation
//! (`$VAR`, `${VAR}`, `${VAR:-default}`, leading `~`) so volatile Nix
//! store paths can be injected via `nix shell` instead of being baked
//! into the committed config.

use indexmap::IndexMap;
use serde::Deserialize;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Name of the hidden per-project directory.
pub const MARKI_DIR: &str = ".marki";

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// Directory of `.md` cards to sync. May or may not be a git repo;
    /// marki itself never shells out to git. Defaults to the project
    /// root (the directory containing `.marki/`, or the current
    /// directory when there is none).
    #[serde(default)]
    pub cards_dir: PathBuf,

    /// Directory containing Lua model scripts (`<name>.lua` +
    /// optional `<name>.css`). Default: `<.marki>/models/`.
    #[serde(default)]
    pub models_dir: Option<PathBuf>,

    /// Directory containing shared Lua libraries importable via
    /// `require "..."`. Default: `<.marki>/lib/`.
    #[serde(default)]
    pub lib_dir: Option<PathBuf>,

    /// Path to the Anki collection file (`.anki2`) this repo syncs into.
    /// Written directly (no AnkiConnect); its sibling `media/` directory and
    /// `media.db` receive renderer-emitted assets. Relative paths resolve
    /// against the project root. Required for `push`/`status`/`watch`/`prune`.
    #[serde(default)]
    pub collection: Option<PathBuf>,

    /// Seconds between reconciliation heartbeat passes in watch mode.
    #[serde(default = "default_sync_interval", with = "duration_secs")]
    pub sync_interval: Duration,

    /// Debounce window for inotify events, in milliseconds.
    #[serde(default = "default_debounce_ms")]
    pub debounce_ms: u64,

    /// Named media SVG/audio sources for the `media` block renderer.
    /// Each key is a source name usable as a prefix in the DSL
    /// (`src = "circle/de"`), and the value is the directory containing
    /// the media files. Order matters: when no prefix is given, sources
    /// are searched in definition order. The built-in `<.marki>/media/`
    /// directory is always searched *first*, ahead of these.
    #[serde(default)]
    pub media_sources: IndexMap<String, PathBuf>,

    /// Path to the `typst` CLI binary used to render `typst` blocks.
    /// When `None`, ` ```typst ` blocks fall through to syntax highlighting.
    /// The user controls how Typst is installed (with which fonts,
    /// packages, or pinned version) — marki just invokes whatever path
    /// is configured here.
    #[serde(default)]
    pub typst_binary: Option<PathBuf>,

    /// Project-level defaults and path rules for `map` blocks. Merged
    /// underneath each card's own block (the author always wins). See
    /// [`marki_map::MapDefaults`].
    #[serde(default)]
    pub map: marki_map::MapDefaults,

    /// The `.marki/` directory this config is anchored to (where
    /// `models/`, `lib/`, and `media/` live). Set during discovery; never
    /// read from the TOML file.
    #[serde(skip)]
    pub anchor_dir: PathBuf,

    /// The project root (parent of `.marki/`, or the current directory
    /// when there is none). Default `cards_dir` and the base for
    /// relative config paths. Set during discovery; never from TOML.
    #[serde(skip)]
    pub project_root: PathBuf,
}

fn default_sync_interval() -> Duration {
    Duration::from_secs(300)
}
fn default_debounce_ms() -> u64 {
    250
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

impl Default for Config {
    fn default() -> Self {
        Self {
            cards_dir: PathBuf::new(),
            models_dir: None,
            lib_dir: None,
            collection: None,
            sync_interval: Duration::from_secs(300),
            debounce_ms: 250,
            media_sources: Default::default(),
            typst_binary: None,
            map: Default::default(),
            anchor_dir: PathBuf::new(),
            project_root: PathBuf::new(),
        }
    }
}

/// Where a config came from, so the loader can report it and anchor
/// relative paths correctly.
#[derive(Debug, Clone)]
pub struct Discovery {
    /// The resolved config file path, if one exists on disk.
    pub config_path: Option<PathBuf>,
    /// The `.marki/` directory state/models/lib/media anchor to.
    pub anchor_dir: PathBuf,
    /// The project root (parent of `.marki/`, or cwd).
    pub project_root: PathBuf,
}

impl Config {
    /// Legacy global config path: `$XDG_CONFIG_HOME/marki/config.toml`.
    pub fn global_path() -> Option<PathBuf> {
        dirs::config_dir().map(|c| c.join("marki").join("config.toml"))
    }

    /// Discover the project layout by walking up from `start` looking
    /// for a `.marki/` directory. An explicit `--config` / `$MARKI_CONFIG`
    /// override short-circuits the walk and anchors to that file's parent.
    pub fn discover(start: &Path, explicit: Option<&Path>) -> Discovery {
        if let Some(cfg) = explicit {
            // Anchor to the directory holding the explicit config. If it
            // is itself a `.marki/`, the project root is its parent.
            let anchor = cfg.parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("."));
            let project_root = if anchor.file_name().map(|n| n == MARKI_DIR).unwrap_or(false) {
                anchor.parent().map(Path::to_path_buf).unwrap_or_else(|| anchor.clone())
            } else {
                anchor.clone()
            };
            return Discovery {
                config_path: Some(cfg.to_path_buf()),
                anchor_dir: anchor,
                project_root,
            };
        }

        // Walk up from `start` looking for `<dir>/.marki/`.
        let mut cur = Some(start);
        while let Some(dir) = cur {
            let candidate = dir.join(MARKI_DIR);
            if candidate.is_dir() {
                let config_path = candidate.join("config.toml");
                return Discovery {
                    config_path: config_path.exists().then_some(config_path),
                    anchor_dir: candidate,
                    project_root: dir.to_path_buf(),
                };
            }
            cur = dir.parent();
        }

        // No `.marki/` anywhere: fall back to the legacy global config
        // (for the daemon / pre-repo setups), anchored to cwd.
        let global = Self::global_path().filter(|p| p.exists());
        Discovery {
            anchor_dir: global
                .as_ref()
                .and_then(|p| p.parent())
                .map(Path::to_path_buf)
                .unwrap_or_else(|| start.to_path_buf()),
            project_root: start.to_path_buf(),
            config_path: global,
        }
    }

    /// Load and fully resolve a config for the given discovery result.
    /// Applies env interpolation, anchors relative paths, and fills in
    /// defaults. A missing config file yields pure defaults.
    pub fn load(disc: &Discovery) -> anyhow::Result<Self> {
        let mut cfg = match &disc.config_path {
            Some(p) => {
                let raw = std::fs::read_to_string(p)
                    .map_err(|e| anyhow::anyhow!("read config {}: {e}", p.display()))?;
                toml::from_str::<Config>(&raw)
                    .map_err(|e| anyhow::anyhow!("parse config {}: {e}", p.display()))?
            }
            None => Config::default(),
        };
        cfg.anchor_dir = disc.anchor_dir.clone();
        cfg.project_root = disc.project_root.clone();
        cfg.expand_env()?;
        Ok(cfg)
    }

    /// Expand `$VAR` / `${VAR}` / `${VAR:-default}` / leading `~` in
    /// every path/string-valued field. Fails fast on an undefined
    /// variable that has no `:-default`.
    pub fn expand_env(&mut self) -> anyhow::Result<()> {
        // cards_dir keeps its empty sentinel (→ project root) un-expanded.
        if !self.cards_dir.as_os_str().is_empty() {
            expand_path(&mut self.cards_dir, "cards_dir")?;
        }
        if let Some(p) = self.models_dir.as_mut() {
            expand_path(p, "models_dir")?;
        }
        if let Some(p) = self.lib_dir.as_mut() {
            expand_path(p, "lib_dir")?;
        }
        if let Some(p) = self.typst_binary.as_mut() {
            expand_path(p, "typst_binary")?;
        }
        if let Some(p) = self.collection.as_mut() {
            expand_path(p, "collection")?;
        }
        for (name, dir) in self.media_sources.iter_mut() {
            let key = format!("media_sources.{name}");
            expand_path(dir, &key)?;
        }
        Ok(())
    }

    /// Resolved models directory. Falls back to `<.marki>/models/`.
    pub fn resolved_models_dir(&self) -> PathBuf {
        self.models_dir
            .clone()
            .map(|p| self.anchor_relative(p))
            .unwrap_or_else(|| self.anchor_dir.join("models"))
    }

    /// Resolved lib directory. Falls back to `<.marki>/lib/`.
    pub fn resolved_lib_dir(&self) -> PathBuf {
        self.lib_dir
            .clone()
            .map(|p| self.anchor_relative(p))
            .unwrap_or_else(|| self.anchor_dir.join("lib"))
    }

    /// The built-in, git-tracked primary media directory: `<.marki>/media/`.
    pub fn builtin_media_dir(&self) -> PathBuf {
        self.anchor_dir.join("media")
    }

    /// Resolved cards directory. Falls back to the project root.
    pub fn resolved_cards_dir(&self) -> PathBuf {
        if self.cards_dir.as_os_str().is_empty() {
            self.project_root.clone()
        } else {
            self.project_root.join(&self.cards_dir)
        }
    }

    /// Resolved collection file (`.anki2`), anchored to the project root when
    /// the configured path is relative. `None` when unconfigured.
    pub fn resolved_collection(&self) -> Option<PathBuf> {
        self.collection.clone().map(|p| self.anchor_relative(p))
    }

    /// The `media/` directory beside the collection file, where renderer
    /// assets are written. `None` when the collection is unconfigured.
    pub fn media_dir(&self) -> Option<PathBuf> {
        self.resolved_collection()
            .and_then(|c| c.parent().map(|p| p.join("media")))
    }

    /// The server media database (`media.db`) beside the collection file.
    /// `None` when the collection is unconfigured.
    pub fn media_db_path(&self) -> Option<PathBuf> {
        self.resolved_collection()
            .and_then(|c| c.parent().map(|p| p.join("media.db")))
    }

    /// Resolve a possibly-relative config path against the project root.
    fn anchor_relative(&self, p: PathBuf) -> PathBuf {
        if p.is_absolute() {
            p
        } else {
            self.project_root.join(p)
        }
    }
}

/// Helper that expands a `PathBuf` in place, reporting `field` on error.
fn expand_path(p: &mut PathBuf, field: &str) -> anyhow::Result<()> {
    let s = p.to_string_lossy();
    let expanded = expand_env_str(&s, field)?;
    *p = PathBuf::from(expanded);
    Ok(())
}

/// Expand shell-style variables and a leading `~` in `input`.
///
/// Supported: `$NAME`, `${NAME}`, `${NAME:-default}`, and a leading `~`
/// (home directory) -- including inside a `:-default` branch, matching
/// shell tilde-expansion semantics. An undefined variable without a
/// `:-default` is an error naming the variable and `field`.
fn expand_env_str(input: &str, field: &str) -> anyhow::Result<String> {
    let mut s = String::with_capacity(input.len());
    let rest = expand_leading_tilde(input, field)?;
    let rest = rest.as_str();

    let bytes = rest.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if c == b'$' {
            // `${NAME}` / `${NAME:-default}`
            if i + 1 < bytes.len() && bytes[i + 1] == b'{' {
                let end = rest[i + 2..]
                    .find('}')
                    .map(|off| i + 2 + off)
                    .ok_or_else(|| anyhow::anyhow!("{field}: unterminated `${{` in `{input}`"))?;
                let inner = &rest[i + 2..end];
                let (name, default) = match inner.split_once(":-") {
                    Some((n, d)) => (n, Some(d)),
                    None => (inner, None),
                };
                s.push_str(&lookup(name, default, field)?);
                i = end + 1;
            } else {
                // `$NAME` — NAME is [A-Za-z_][A-Za-z0-9_]*
                let start = i + 1;
                let mut j = start;
                while j < bytes.len()
                    && (bytes[j].is_ascii_alphanumeric() || bytes[j] == b'_')
                {
                    j += 1;
                }
                if j == start {
                    // Lone `$` — keep literal.
                    s.push('$');
                    i += 1;
                    continue;
                }
                let name = &rest[start..j];
                s.push_str(&lookup(name, None, field)?);
                i = j;
            }
        } else {
            // Copy one UTF-8 char starting at byte i.
            let ch_len = utf8_len(c);
            s.push_str(&rest[i..i + ch_len]);
            i += ch_len;
        }
    }
    Ok(s)
}

/// Expand a leading `~` (only when it starts `input` and is followed by
/// `/` or end, matching shell behaviour). `~user` is not supported and
/// is left as-is.
fn expand_leading_tilde(input: &str, field: &str) -> anyhow::Result<String> {
    let Some(after) = input.strip_prefix('~') else {
        return Ok(input.to_string());
    };
    if after.is_empty() || after.starts_with('/') {
        let home = dirs::home_dir()
            .ok_or_else(|| anyhow::anyhow!("{field}: cannot expand `~` (no home directory)"))?;
        Ok(format!("{}{}", home.to_string_lossy(), after))
    } else {
        Ok(input.to_string())
    }
}

fn lookup(name: &str, default: Option<&str>, field: &str) -> anyhow::Result<String> {
    match std::env::var(name) {
        Ok(v) => Ok(v),
        Err(_) => match default {
            Some(d) => expand_leading_tilde(d, field),
            None => Err(anyhow::anyhow!(
                "{field}: environment variable `${name}` is not set \
                 (use `${{{name}:-default}}` to provide a fallback)"
            )),
        },
    }
}

fn utf8_len(first: u8) -> usize {
    match first {
        0x00..=0x7F => 1,
        0xC0..=0xDF => 2,
        0xE0..=0xEF => 3,
        _ => 4,
    }
}

/// Scaffold a `.marki/` project directory under `root`. Idempotent:
/// creates any missing pieces, never overwrites existing files. Returns
/// the created `.marki/` path.
pub fn init_project(root: &Path) -> anyhow::Result<PathBuf> {
    let anchor = root.join(MARKI_DIR);
    for sub in ["", "models", "lib", "media"] {
        let dir = if sub.is_empty() { anchor.clone() } else { anchor.join(sub) };
        std::fs::create_dir_all(&dir)
            .map_err(|e| anyhow::anyhow!("create {}: {e}", dir.display()))?;
    }
    // Keep the empty content dirs in git.
    for sub in ["models", "lib", "media"] {
        let keep = anchor.join(sub).join(".gitkeep");
        if !keep.exists() {
            let _ = std::fs::write(&keep, b"");
        }
    }
    let cfg = anchor.join("config.toml");
    if !cfg.exists() {
        std::fs::write(&cfg, STARTER_CONFIG)
            .map_err(|e| anyhow::anyhow!("write {}: {e}", cfg.display()))?;
    }
    Ok(anchor)
}

const STARTER_CONFIG: &str = r#"# marki project config — lives in `.marki/`, committed with your cards.
#
# Everything is optional. By default marki syncs the `.md` cards in this
# repo and renders them with the models in `.marki/models/`.

# cards_dir defaults to the repo root (the directory containing .marki/).
# Relative paths resolve against that root. Uncomment to override:
# cards_dir = "cards"

# Path to the Anki collection file (.anki2) this repo syncs into. Written
# directly -- no AnkiConnect. Its sibling `media/` dir and `media.db` receive
# rendered assets. Relative paths resolve against the repo root. Pair with
# env interpolation to keep a volatile profile path out of the committed file:
# collection = "${ANKI_COLLECTION:-~/.local/share/Anki2/User 1/collection.anki2}"

# Path to the `typst` CLI for ```typst``` blocks. Pair with `nix shell`
# and env interpolation so the volatile /nix/store path isn't committed:
# typst_binary = "${TYPST_BIN:-typst}"

# Named media sources for ```media``` blocks. The built-in
# `.marki/media/` directory is always searched FIRST; these add more.
# Values support $VAR / ${VAR} / ${VAR:-default} / ~ interpolation, so a
# `nix shell` can inject store paths without baking them in here:
# [media_sources]
# circle = "${CIRCLE_FLAGS}/share/circle-flags-svg"
# flags  = "${HAYLEOX_FLAGS}/share/hayleox-flags"

# Project-wide defaults for ```map``` blocks, merged UNDER each card's own
# block (the card always wins). `[map.defaults]` applies everywhere;
# `[[map.rules]]` scopes overrides to a glob matched against the card path
# relative to cards_dir. Several matching rules layer in order.
# [map.defaults]
# style = "atlas"
# [map.defaults.viewport]
# simplify_px = 1.0
#
# [[map.rules]]
# match = "Geography/**"
# [map.rules.defaults.viewport]
# cluster_factor = 0.3
"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(name: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("marki-cfg-{}-{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&p);
        std::fs::create_dir_all(&p).unwrap();
        p
    }

    // ---------- env interpolation ----------

    #[test]
    fn expands_dollar_and_brace() {
        unsafe { std::env::set_var("MARKI_T_A", "/opt/x") };
        assert_eq!(expand_env_str("$MARKI_T_A/y", "f").unwrap(), "/opt/x/y");
        assert_eq!(expand_env_str("${MARKI_T_A}/y", "f").unwrap(), "/opt/x/y");
    }

    #[test]
    fn expands_default_when_unset() {
        let s = expand_env_str("${MARKI_T_UNSET_XYZ:-/fallback}", "f").unwrap();
        assert_eq!(s, "/fallback");
    }

    #[test]
    fn errors_on_undefined_without_default() {
        let err = expand_env_str("$MARKI_T_DEFINITELY_UNSET", "media_sources.flags").unwrap_err();
        let msg = format!("{err}");
        assert!(msg.contains("MARKI_T_DEFINITELY_UNSET"), "{msg}");
        assert!(msg.contains("media_sources.flags"), "{msg}");
    }

    #[test]
    fn expands_tilde_home() {
        let home = dirs::home_dir().unwrap();
        let out = expand_env_str("~/cards", "f").unwrap();
        assert_eq!(out, format!("{}/cards", home.display()));
        // `~user` is left untouched.
        assert_eq!(expand_env_str("~bob/x", "f").unwrap(), "~bob/x");
    }

    #[test]
    fn expands_tilde_inside_default_branch() {
        // The exact pattern STARTER_CONFIG recommends for `collection`:
        // a leading `~` nested inside a `${VAR:-default}` fallback, not
        // at position 0 of the raw config string.
        let home = dirs::home_dir().unwrap();
        let out = expand_env_str("${MARKI_T_UNSET_COLLECTION:-~/cards/x.anki2}", "f").unwrap();
        assert_eq!(out, format!("{}/cards/x.anki2", home.display()));
    }

    #[test]
    fn lone_dollar_is_literal() {
        assert_eq!(expand_env_str("a $ b", "f").unwrap(), "a $ b");
    }

    #[test]
    fn expand_env_walks_all_fields() {
        unsafe { std::env::set_var("MARKI_T_MEDIA", "/m/flags") };
        let mut cfg = Config::default();
        cfg.media_sources.insert("flags".into(), PathBuf::from("${MARKI_T_MEDIA}"));
        cfg.typst_binary = Some(PathBuf::from("${MARKI_T_UNSET2:-typst}"));
        cfg.expand_env().unwrap();
        assert_eq!(cfg.media_sources["flags"], PathBuf::from("/m/flags"));
        assert_eq!(cfg.typst_binary, Some(PathBuf::from("typst")));
    }

    // ---------- discovery ----------

    #[test]
    fn discovers_dotmarki_walking_up() {
        let root = tmp("disc");
        std::fs::create_dir_all(root.join(".marki")).unwrap();
        std::fs::write(root.join(".marki").join("config.toml"), "").unwrap();
        let nested = root.join("a").join("b");
        std::fs::create_dir_all(&nested).unwrap();

        let disc = Config::discover(&nested, None);
        assert_eq!(disc.anchor_dir, root.join(".marki"));
        assert_eq!(disc.project_root, root);
        assert_eq!(disc.config_path, Some(root.join(".marki").join("config.toml")));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn explicit_config_short_circuits() {
        let root = tmp("explicit");
        let cfg = root.join("custom.toml");
        std::fs::write(&cfg, "").unwrap();
        let disc = Config::discover(&root, Some(&cfg));
        assert_eq!(disc.config_path, Some(cfg));
        assert_eq!(disc.anchor_dir, root);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn defaults_anchor_to_dotmarki() {
        let root = tmp("anchor");
        let anchor = root.join(".marki");
        std::fs::create_dir_all(&anchor).unwrap();
        let disc = Discovery {
            config_path: None,
            anchor_dir: anchor.clone(),
            project_root: root.clone(),
        };
        let cfg = Config::load(&disc).unwrap();
        assert_eq!(cfg.resolved_models_dir(), anchor.join("models"));
        assert_eq!(cfg.resolved_lib_dir(), anchor.join("lib"));
        assert_eq!(cfg.builtin_media_dir(), anchor.join("media"));
        // cards_dir defaults to the project root.
        assert_eq!(cfg.resolved_cards_dir(), root);
        let _ = std::fs::remove_dir_all(&root);
    }

    // ---------- init scaffolder ----------

    #[test]
    fn init_creates_layout_idempotently() {
        let root = tmp("init");
        let anchor = init_project(&root).unwrap();
        assert!(anchor.join("config.toml").is_file());
        assert!(anchor.join("models").is_dir());
        assert!(anchor.join("lib").is_dir());
        assert!(anchor.join("media").is_dir());

        // Editing the config then re-running must not clobber it.
        std::fs::write(anchor.join("config.toml"), "cards_dir = \"keep\"\n").unwrap();
        init_project(&root).unwrap();
        let kept = std::fs::read_to_string(anchor.join("config.toml")).unwrap();
        assert_eq!(kept, "cards_dir = \"keep\"\n");
        let _ = std::fs::remove_dir_all(&root);
    }
}
