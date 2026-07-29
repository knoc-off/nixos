//! rhizome -- Trilium notes in Neovim.
//!
//! The binary is the engine: ETAPI access, segmentation, conversion, splicing.
//! Neovim talks to it over stdio; the subcommands here exist for development
//! and for auditing a vault before trusting the write path with it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

mod index;
mod lsp;
mod meta;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use rhizome_core::segment::{BlockKind, OpaqueReason, Stats};
use rhizome_core::{Escaping, segment, splice};

#[derive(Parser)]
#[command(
    name = "rhizome",
    version,
    about = "Trilium notes over ETAPI, honestly"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Report how much of a corpus is editable as prose.
    ///
    /// Point this at a directory of note HTML before trusting a vault to the
    /// write path. It answers the only question that matters: what fraction of
    /// blocks can be proven to round-trip?
    Spike {
        /// Directory searched recursively for `.html` files.
        dir: PathBuf,
        /// List the source of every block that could not be made transparent.
        #[arg(long)]
        show_opaque: bool,
        /// Cap on how many opaque samples to print.
        #[arg(long, default_value_t = 20)]
        samples: usize,
    },
    /// Segment one HTML file and print the resulting blocks.
    Show {
        file: PathBuf,
        /// Print the Markdown rendering of transparent blocks.
        #[arg(long)]
        markdown: bool,
    },
    /// Assert that segmenting and re-splicing a file changes nothing.
    ///
    /// This is the property the whole write path depends on. Exits non-zero on
    /// any byte difference.
    Check { dir: PathBuf },
    /// Show original vs reproduced HTML for blocks that failed verification.
    ///
    /// Verification failures are rule bugs: a rule claimed a block and got it
    /// wrong. This is how you find out which.
    Diff {
        dir: PathBuf,
        #[arg(long, default_value_t = 10)]
        samples: usize,
    },
    /// Render a note to buffer text and parse it straight back, reporting the
    /// first block that fails to survive the trip.
    Roundtrip { file: PathBuf },
    /// Speak LSP over stdio. This is how Neovim drives it.
    ///
    /// The note lifecycle rides on custom `rhizome/*` requests, because
    /// `didSave` is a notification and cannot return the spliced content.
    Lsp {
        /// Trilium server root, e.g. https://trilium.example.com
        #[arg(long, env = "RHIZOME_URL")]
        url: String,
        /// ETAPI token. Prefer the env var over the flag.
        #[arg(long, env = "RHIZOME_TOKEN", hide_env_values = true)]
        token: String,
    },
    /// Check that the server is reachable and the token works.
    ///
    /// Uses the same client as `lsp`, so a pass here means the editor will
    /// connect too. Prints JSON for `:checkhealth rhizome` to read.
    Doctor {
        #[arg(long, env = "RHIZOME_URL")]
        url: String,
        #[arg(long, env = "RHIZOME_TOKEN", hide_env_values = true)]
        token: String,
    },
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rhizome=info".into()),
        )
        .with_writer(std::io::stderr)
        .init();

    match Cli::parse().command {
        Command::Spike {
            dir,
            show_opaque,
            samples,
        } => spike(&dir, show_opaque, samples),
        Command::Show { file, markdown } => show(&file, markdown),
        Command::Check { dir } => check(&dir),
        Command::Diff { dir, samples } => diff(&dir, samples),
        Command::Roundtrip { file } => roundtrip(&file),
        Command::Lsp { url, token } => lsp::serve(rhizome_etapi::Client::new(url, token)?),
        Command::Doctor { url, token } => doctor(url, token),
    }
}

/// Connect, and report what happened as JSON on stdout.
///
/// Exits non-zero on failure so a caller can branch on the status alone.
fn doctor(url: String, token: String) -> Result<()> {
    let report = match rhizome_etapi::Client::new(url, token)
        .and_then(|client| client.app_info().map(|info| (client, info)))
    {
        Ok((_, info)) => serde_json::json!({
            "ok": true,
            "appVersion": info["appVersion"],
            "dbVersion": info["dbVersion"],
        }),
        Err(error) => serde_json::json!({ "ok": false, "error": error.to_string() }),
    };
    println!("{report}");
    if report["ok"] == serde_json::Value::Bool(false) {
        std::process::exit(1);
    }
    Ok(())
}

/// Re-run the conversion for blocks that failed verification and show both
/// attempts `classify` actually makes, each against the reproduced HTML, so
/// the discrepancy that sent the block opaque is visible for both.
fn diff(dir: &Path, samples: usize) -> Result<()> {
    let mut shown = 0usize;
    for file in html_files(dir)? {
        if shown >= samples {
            break;
        }
        let html = std::fs::read_to_string(&file)?;
        for block in segment(&html).blocks() {
            if shown >= samples {
                break;
            }
            if !matches!(
                block.kind,
                BlockKind::Opaque {
                    reason: OpaqueReason::VerificationFailed
                }
            ) {
                continue;
            }
            shown += 1;
            let nodes = rhizome_core::parse(&block.source);
            println!("=== {} [{}]", file.display(), block.id);
            println!("--- original\n{}", truncate(&block.source, 300));
            for (label, mode) in [("bare", Escaping::Bare), ("full", Escaping::Full)] {
                let md = rhizome_core::blocks_to_markdown(&nodes, mode).unwrap_or_default();
                let reproduced = rhizome_core::markdown_to_html(&md);
                println!("--- {label} markdown\n{}", truncate(&md, 300));
                println!("--- {label} reproduced\n{}", truncate(&reproduced, 300));
            }
            println!();
        }
    }
    Ok(())
}

fn html_files(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(path) = stack.pop() {
        for entry in std::fs::read_dir(&path).with_context(|| format!("reading {path:?}"))? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "html") {
                out.push(path);
            }
        }
    }
    out.sort();
    Ok(out)
}

fn spike(dir: &Path, show_opaque: bool, samples: usize) -> Result<()> {
    let files = html_files(dir)?;
    let mut totals = Stats::default();
    let mut notes_fully_transparent = 0usize;
    let mut opaque_tags: BTreeMap<String, usize> = BTreeMap::new();
    let mut shown = 0usize;

    for file in &files {
        let html = std::fs::read_to_string(file)?;
        let segments = segment(&html);
        let stats = segments.stats();

        totals.total += stats.total;
        totals.transparent += stats.transparent;
        totals.spacer += stats.spacer;
        totals.no_rule += stats.no_rule;
        totals.verification_failed += stats.verification_failed;
        totals.unparseable += stats.unparseable;
        totals.ambiguous += stats.ambiguous;
        if stats.opaque() == 0 {
            notes_fully_transparent += 1;
        }

        for block in segments.blocks() {
            if let BlockKind::Opaque { reason } = &block.kind {
                *opaque_tags
                    .entry(opaque_key(&block.source, *reason))
                    .or_default() += 1;
                if show_opaque && shown < samples {
                    shown += 1;
                    println!("--- {reason:?} in {}", file.display());
                    println!("{}\n", truncate(&block.source, 400));
                }
            }
        }
    }

    println!("notes            {}", files.len());
    println!(
        "  fully transparent {notes_fully_transparent} ({:.1}%)",
        pct(notes_fully_transparent, files.len())
    );
    println!("blocks           {}", totals.total);
    println!(
        "  transparent       {} ({:.1}%)",
        totals.transparent,
        totals.transparent_ratio() * 100.0
    );
    println!(
        "  opaque            {} ({:.1}%)",
        totals.opaque(),
        pct(totals.opaque(), totals.total)
    );
    println!("    no rule           {}", totals.no_rule);
    println!("    verify failed     {}", totals.verification_failed);
    println!("    unparseable       {}", totals.unparseable);
    println!("    ambiguous         {}", totals.ambiguous);
    println!("  spacer            {}", totals.spacer);

    println!("\ntop opaque constructs:");
    let mut ranked: Vec<_> = opaque_tags.into_iter().collect();
    ranked.sort_by_key(|(_, count)| std::cmp::Reverse(*count));
    for (key, count) in ranked.iter().take(15) {
        println!("  {count:5}  {key}");
    }

    Ok(())
}

/// Group opaque blocks by their root tag plus classes, so the report points at
/// which construct to write a rule for next.
fn opaque_key(source: &str, reason: OpaqueReason) -> String {
    let nodes = rhizome_core::parse(source);
    let Some(el) = nodes.iter().find_map(|n| n.element()) else {
        return format!("{reason:?} <text>");
    };
    let classes = el.classes();
    let tag = if classes.is_empty() {
        format!("<{}>", el.name)
    } else {
        format!("<{} class=\"{}\">", el.name, classes.join(" "))
    };
    format!("{reason:?} {tag}")
}

fn show(file: &Path, markdown: bool) -> Result<()> {
    let html = std::fs::read_to_string(file)?;
    let segments = segment(&html);
    for block in segments.blocks() {
        match &block.kind {
            BlockKind::Transparent { markdown: md } => {
                println!("[{}] transparent", block.id);
                if markdown {
                    println!("{md}\n");
                }
            }
            BlockKind::Spacer => println!("[{}] spacer", block.id),
            BlockKind::Opaque { reason } => {
                println!("[{}] opaque ({reason:?})", block.id);
                println!("{}\n", truncate(&block.source, 200));
            }
        }
    }
    let stats = segments.stats();
    println!(
        "{} blocks, {} transparent ({:.1}%)",
        stats.total,
        stats.transparent,
        stats.transparent_ratio() * 100.0
    );
    Ok(())
}

fn check(dir: &Path) -> Result<()> {
    let files = html_files(dir)?;
    let mut failures = 0usize;
    for file in &files {
        let html = std::fs::read_to_string(file)?;
        let segments = segment(&html);
        let spliced = splice(&segments, &BTreeMap::new());
        if spliced != html {
            failures += 1;
            println!("DIFFERS {}", file.display());
        }
    }
    println!(
        "{}/{} files splice back byte-identical",
        files.len() - failures,
        files.len()
    );
    if failures > 0 {
        anyhow::bail!("{failures} files did not round-trip");
    }
    Ok(())
}

fn roundtrip(file: &Path) -> Result<()> {
    let html = std::fs::read_to_string(file)?;
    let segments = segment(&html);
    let text = rhizome_core::buffer::render(&segments);
    let rebuilt = rhizome_core::buffer::parse(&text, &segments);

    let before: Vec<String> = segments
        .blocks()
        .map(|b| b.source.trim().to_string())
        .collect();
    let after_seg = segment(&rebuilt);
    let after: Vec<String> = after_seg
        .blocks()
        .map(|b| b.source.trim().to_string())
        .collect();

    if before == after {
        println!("ok: {} blocks survived", before.len());
        return Ok(());
    }
    println!("block count {} -> {}", before.len(), after.len());
    for (i, (a, b)) in before.iter().zip(after.iter()).enumerate() {
        if a != b {
            println!("first difference at block {i}");
            println!("--- before\n{}", truncate(a, 400));
            println!("--- after\n{}", truncate(b, 400));
            return Ok(());
        }
    }
    let (long, label) = if before.len() > after.len() {
        (&before, "before")
    } else {
        (&after, "after")
    };
    println!("extra blocks in {label}:");
    for extra in long.iter().skip(before.len().min(after.len())).take(3) {
        println!("{}", truncate(extra, 300));
    }
    Ok(())
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        return s.to_string();
    }
    let cut: String = s.chars().take(max).collect();
    format!("{cut}…")
}

fn pct(part: usize, whole: usize) -> f64 {
    if whole == 0 {
        return 0.0;
    }
    part as f64 / whole as f64 * 100.0
}
