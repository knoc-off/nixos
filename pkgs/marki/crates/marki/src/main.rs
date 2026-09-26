//! `marki` CLI + daemon entry point.

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use marki::config::Config;
use marki::fmt as fmt_mod;
use marki::project::Project;
use marki::watch::{Tick, run as run_watch};
use std::path::{Path, PathBuf};
use std::time::Duration;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(
    name = "marki",
    version,
    about = "Sync a markdown card repo with an Anki collection -- a one-shot CLI (optional watch daemon).",
    long_about = "marki keeps a directory of markdown flashcards in sync with an Anki \
collection file (`.anki2`), which it writes directly.\n\nIt is repo-centric: run it from \
inside a flashcard repo and it discovers a hidden `.marki/` directory (git-style, walking up \
from the current directory) holding the config, models, libraries and media that define your \
cards. `marki init` scaffolds one.\n\n\
With no subcommand, marki runs a single `push` (scan -> reconcile -> write) and exits."
)]
struct Cli {
    /// Path to a config file. By default marki discovers the nearest
    /// `.marki/config.toml` (walking up from the current directory),
    /// then falls back to `$XDG_CONFIG_HOME/marki/config.toml`.
    #[arg(long, env = "MARKI_CONFIG", global = true)]
    config: Option<PathBuf>,

    /// Override the cards directory (default: the repo root).
    #[arg(long, global = true)]
    cards_dir: Option<PathBuf>,

    /// Override the Anki collection file (`.anki2`) to write into.
    #[arg(long, env = "MARKI_COLLECTION", global = true)]
    collection: Option<PathBuf>,

    /// Override the directory containing media files used by ```media``` blocks.
    /// Adds a single unnamed source (searched last, after any [media_sources]
    /// configured in the config file).
    #[arg(long, env = "MARKI_MEDIA_DIR", global = true)]
    media_dir: Option<PathBuf>,

    /// Path to the `typst` CLI binary, used to render ```typst``` blocks.
    /// When unset, ```typst``` blocks fall through to syntax highlighting.
    #[arg(long, env = "MARKI_TYPST", global = true)]
    typst_binary: Option<PathBuf>,

    /// Increase log verbosity. Repeat for more detail: `-v` enables
    /// `debug`, `-vv` enables `trace`. Overridden by an explicit
    /// `RUST_LOG`/env filter when one is set.
    #[arg(short = 'v', long = "verbose", global = true, action = clap::ArgAction::Count)]
    verbose: u8,

    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Scaffold a `.marki/` project (config, models/, lib/, media/) in
    /// the current directory. Idempotent — never overwrites existing
    /// files. Run this once to turn a folder of cards into a marki repo.
    Init,
    /// Mint `#id(...)` for any card that doesn't have one. Pure disk op;
    /// no Anki needed. Meant to be run in CI or as a pre-commit step.
    Fmt,
    /// Run a single reconcile cycle and exit. This is the default when
    /// no subcommand is given.
    Push {
        /// Hard-delete orphaned notes (collection notes with no matching
        /// `.md`) instead of the default soft-delete (suspend + `marki::orphan`
        /// tag). Irreversible — destroys scheduling history. Even with this
        /// flag, nothing is pruned during a cycle that had render errors.
        #[arg(long)]
        prune: bool,
        /// Push into a throwaway copy of the collection, check the result,
        /// and report; the real collection and media are not touched.
        #[arg(long)]
        simulate: bool,
    },
    /// Validate without writing: render every card (reporting model and
    /// block errors), and check the collection's structure.
    Check,
    /// Long-running daemon: watch the cards directory and push on change.
    Watch,
    /// Read-only diff view (added / updated / moved / deleted / unformatted).
    Status,
    /// Permanently delete notes previously quarantined (soft-deleted):
    /// every note tagged `marki::orphan`. Run this once you've confirmed
    /// the suspended notes really should be gone.
    Prune {
        /// Show what would be deleted without touching Anki.
        #[arg(long)]
        dry_run: bool,
    },
    /// Render one card offline (no collection) to `<out>/preview.html`
    /// with every card front and back and the model CSS, plus its assets.
    Render {
        /// The card .md to render.
        file: PathBuf,
        /// Directory to write the preview and asset files into.
        #[arg(long, default_value = "out")]
        out: PathBuf,
        /// Dump rendered assets (SVGs etc.) to stdout instead of writing
        /// files. With multiple assets each is prefixed by an
        /// `<!-- asset: NAME -->` comment.
        #[arg(long)]
        stdout: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    // Verbosity: an explicit RUST_LOG/env filter always wins; otherwise
    // `-v` bumps the default level. Logs go to stderr so stdout stays
    // clean for `render-map --stdout`.
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        let level = match cli.verbose {
            0 => "info",
            1 => "debug",
            _ => "trace",
        };
        EnvFilter::new(level)
    });
    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_target(false)
        .with_writer(std::io::stderr)
        .init();

    // Render needs the project (models, media) but no collection.
    if let Some(Cmd::Render { file, out, stdout }) = &cli.cmd {
        let mut project = Project::new(load_config(&cli)?);
        return cmd_render(&mut project, file, out, *stdout);
    }

    // `init` only scaffolds the current directory; no config load needed.
    if let Some(Cmd::Init) = &cli.cmd {
        return cmd_init();
    }

    let cfg = load_config(&cli)?;

    // No subcommand → run a single push (one-shot first).
    let cmd = cli.cmd.unwrap_or(Cmd::Push { prune: false, simulate: false });

    if let Cmd::Fmt = cmd {
        return cmd_fmt(&cfg);
    }
    if let Cmd::Prune { dry_run } = cmd {
        return cmd_prune(&Project::new(cfg), dry_run);
    }
    let mut project = Project::new(cfg);
    let mut col = project.open_collection()?;
    match cmd {
        Cmd::Push { prune, simulate: true } => {
            let sim = project.simulate(&col, prune)?;
            print_changes(&project, &sim.outcome);
            for e in sim.outcome.errors.iter().chain(&sim.problems) {
                eprintln!("problem: {e}");
            }
            anyhow::ensure!(sim.ok(), "simulation found problems; nothing was written");
            println!("simulation clean (plan {})", sim.plan_hash);
            Ok(())
        }
        Cmd::Push { prune, simulate: false } => cmd_push(&mut project, &mut col, prune),
        Cmd::Status => {
            let outcome = run_cycle(&mut project, &mut col, true, false)?;
            print_changes(&project, &outcome);
            Ok(())
        }
        Cmd::Watch => cmd_watch(&mut project, &mut col),
        Cmd::Check => {
            let outcome = project.cycle(&mut col, true, false)?;
            let problems = col.check()?;
            for e in outcome.errors.iter().chain(&problems) {
                println!("{e}");
            }
            anyhow::ensure!(
                outcome.errors.is_empty() && problems.is_empty(),
                "{} problem(s)",
                outcome.errors.len() + problems.len()
            );
            println!("ok");
            Ok(())
        }
        Cmd::Init | Cmd::Fmt | Cmd::Prune { .. } | Cmd::Render { .. } => unreachable!(),
    }
}

fn load_config(cli: &Cli) -> Result<Config> {
    let cwd = std::env::current_dir().context("get current directory")?;
    let disc = Config::discover(&cwd, cli.config.as_deref());
    if let Some(p) = &disc.config_path {
        tracing::debug!(config = %p.display(), anchor = %disc.anchor_dir.display(), "loaded config");
    } else {
        tracing::debug!(anchor = %disc.anchor_dir.display(), "no config file; using defaults");
    }
    let mut cfg = Config::load(&disc)?;
    apply_cli_overrides(&mut cfg, cli)?;
    Ok(cfg)
}

/// Apply `--cards-dir`, `--anki-endpoint`, `--media-dir`, `--typst-binary`
/// overrides on top of the loaded config. `--media-dir` adds a single
/// source searched after both the built-in media dir and config sources.
fn apply_cli_overrides(cfg: &mut Config, cli: &Cli) -> Result<()> {
    if let Some(p) = &cli.cards_dir {
        cfg.cards_dir = p.clone();
    }
    if let Some(p) = &cli.collection {
        cfg.collection = Some(p.clone());
    }
    if let Some(p) = &cli.media_dir {
        cfg.media_sources
            .entry("_default".into())
            .or_insert_with(|| p.clone());
    }
    if let Some(p) = &cli.typst_binary {
        cfg.typst_binary = Some(p.clone());
    }
    Ok(())
}

fn run_cycle(
    project: &mut Project,
    col: &mut marki_anki::Collection,
    dry_run: bool,
    prune: bool,
) -> Result<marki::sync::Outcome> {
    let outcome = project.cycle(col, dry_run, prune)?;
    tracing::info!(
        "cycle: +{} ~{} ->{} -{} (quarantined {}, skipped-prune {}, unformatted {}, {} errors)",
        outcome.added,
        outcome.updated,
        outcome.moved,
        outcome.deleted,
        outcome.quarantined,
        outcome.skipped_prune,
        outcome.unformatted,
        outcome.errors.len(),
    );
    for e in &outcome.errors {
        tracing::warn!("{e}");
    }
    Ok(outcome)
}

/// One line per planned note change, paths relative to the cards dir.
fn print_changes(project: &Project, outcome: &marki::sync::Outcome) {
    for c in &outcome.changes {
        let what = match &c.path {
            Some(p) => p.strip_prefix(&project.cfg.cards_dir).unwrap_or(p).display().to_string(),
            None => format!("#id({})", c.id),
        };
        let kind: &str = (&c.kind).into();
        if c.detail.is_empty() {
            println!("{kind:<12} {what}");
        } else {
            println!("{kind:<12} {what}  ({})", c.detail);
        }
    }
}

/// Scaffold a `.marki/` project in the current directory.
fn cmd_init() -> Result<()> {
    let cwd = std::env::current_dir().context("get current directory")?;
    let anchor = marki::config::init_project(&cwd)?;
    println!("initialized marki project at {}", anchor.display());
    println!("  - edit {}/config.toml", anchor.display());
    println!("  - add models to {}/models/", anchor.display());
    println!("  - add committed media to {}/media/", anchor.display());
    println!("then run `marki` (or `marki push`) from this repo to sync.");
    Ok(())
}

fn cmd_fmt(cfg: &Config) -> Result<()> {
    let outcome = fmt_mod::run(&cfg.resolved_cards_dir())?;
    println!(
        "fmt: formatted {} (minted {}), unchanged {}, warnings {}",
        outcome.formatted, outcome.minted, outcome.unchanged, outcome.errored,
    );
    for e in &outcome.errors {
        eprintln!("warning: {e}");
    }
    Ok(())
}

fn cmd_push(project: &mut Project, col: &mut marki_anki::Collection, prune: bool) -> Result<()> {
    let outcome = run_cycle(project, col, false, prune)?;
    // Surface failures with a non-zero exit so cron/systemd notices, instead
    // of silently "succeeding" while notes failed to render.
    if !outcome.errors.is_empty() {
        anyhow::bail!(
            "cycle completed with {} error(s); no orphans were pruned",
            outcome.errors.len()
        );
    }
    Ok(())
}

/// Permanently delete every note quarantined by a prior soft-delete
/// (`tag:marki::orphan`). Separate, explicit, opt-in step. Reads the
/// collection directly and removes the notes in one transaction.
fn cmd_prune(project: &Project, dry_run: bool) -> Result<()> {
    use marki::anki::model::{MARKER_TAG, ORPHAN_TAG};

    let mut col = project.open_collection()?;
    let managed = col.managed_notes(MARKER_TAG).context("read managed notes")?;
    let note_ids: Vec<i64> = managed
        .iter()
        .filter(|n| n.tags.iter().any(|t| t == ORPHAN_TAG))
        .map(|n| n.note_id)
        .collect();

    if note_ids.is_empty() {
        println!("prune: no quarantined notes (tag:{ORPHAN_TAG})");
        return Ok(());
    }
    if dry_run {
        println!("prune (dry-run): would delete {} quarantined note(s)", note_ids.len());
        return Ok(());
    }
    col.transact(|w| {
        for id in &note_ids {
            w.remove_note(*id)?;
        }
        Ok(())
    })
    .context("delete quarantined notes")?;
    println!("prune: deleted {} quarantined note(s)", note_ids.len());
    Ok(())
}

fn cmd_render(project: &mut Project, file: &Path, out: &Path, to_stdout: bool) -> Result<()> {
    use std::io::Write;

    let source =
        std::fs::read_to_string(file).with_context(|| format!("read {}", file.display()))?;
    let abs = std::path::absolute(file).unwrap_or_else(|_| file.to_path_buf());
    let preview = project.preview(&abs, &source)?;
    for e in &preview.note.errors {
        eprintln!("warning: {e}");
    }
    let assets = &preview.note.assets;

    // --stdout: raw assets only, so `marki render card.md --stdout > map.svg`
    // gives a clean SVG (logs go to stderr).
    if to_stdout {
        let mut w = std::io::stdout().lock();
        for a in assets {
            if assets.len() > 1 {
                writeln!(w, "<!-- asset: {} -->", a.filename)?;
            }
            w.write_all(&a.bytes)?;
            if !a.bytes.ends_with(b"\n") {
                writeln!(w)?;
            }
        }
        return Ok(());
    }

    std::fs::create_dir_all(out).with_context(|| format!("create {}", out.display()))?;
    for a in assets {
        let p = out.join(&a.filename);
        std::fs::write(&p, &a.bytes).with_context(|| format!("write asset {}", p.display()))?;
    }
    let html_path = out.join("preview.html");
    std::fs::write(&html_path, preview.html_page(&file.display().to_string()))
        .with_context(|| format!("write {}", html_path.display()))?;
    println!(
        "wrote {} ({} card(s)) plus {} asset(s) to {}",
        html_path.display(),
        preview.cards.len(),
        assets.len(),
        out.display()
    );
    Ok(())
}

fn cmd_watch(project: &mut Project, col: &mut marki_anki::Collection) -> Result<()> {
    let cfg = project.cfg.clone();
    let debounce = Duration::from_millis(cfg.debounce_ms);
    let heartbeat = cfg.sync_interval;

    tracing::info!(
        "watching {} (debounce={:?} heartbeat={:?})",
        cfg.cards_dir.display(),
        debounce,
        heartbeat
    );

    run_watch(&cfg.cards_dir, debounce, heartbeat, |tick| {
        match tick {
            Tick::Filesystem => tracing::info!("cycle: triggered by filesystem change"),
            Tick::Heartbeat => tracing::info!("cycle: triggered by heartbeat"),
        }
        if let Err(e) = run_cycle(project, col, false, false) {
            tracing::error!("cycle failed: {e:#}");
        }
        Ok(true)
    })
}
