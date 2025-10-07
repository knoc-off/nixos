mod card;
mod generator;
mod highlighter;
mod parser;

use anyhow::{Context, Result};
use clap::Parser as ClapParser;
use std::fs;
use std::path::PathBuf;
use walkdir::WalkDir;

#[derive(ClapParser, Debug)]
#[clap(name = "marki", version, author)]
#[clap(about = "Convert Markdown files to Anki flashcards (.apkg)")]
struct Args {
    /// Input file or directory
    input: PathBuf,

    /// Output .apkg file
    #[clap(short, long, default_value = "output.apkg")]
    output: PathBuf,

    /// Process directories recursively
    #[clap(short, long)]
    recursive: bool,

    /// Deck name (defaults to input file/directory name)
    #[clap(short, long)]
    deck_name: Option<String>,
}

fn find_markdown_files(root: &PathBuf, recursive: bool) -> Vec<PathBuf> {
    dbg!("Finding markdown files", root, recursive);

    let max_depth = if recursive { usize::MAX } else { 1 };

    let files: Vec<PathBuf> = WalkDir::new(root)
        .max_depth(max_depth)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| {
            e.file_type().is_file()
                && e.path()
                    .extension()
                    .and_then(|s| s.to_str())
                    .map(|s| s == "md" || s == "markdown")
                    .unwrap_or(false)
        })
        .map(|e| e.path().to_path_buf())
        .collect();

    dbg!("Found markdown files", files.len());
    for file in &files {
        dbg!("  -", file);
    }

    files
}

fn main() -> Result<()> {
    let args = Args::parse();

    dbg!(&args);

    // Determine if input is file or directory
    let files = if args.input.is_file() {
        dbg!("Input is a file");
        vec![args.input.clone()]
    } else if args.input.is_dir() {
        dbg!("Input is a directory");
        find_markdown_files(&args.input, args.recursive)
    } else {
        anyhow::bail!("Input path does not exist: {}", args.input.display());
    };

    if files.is_empty() {
        anyhow::bail!("No markdown files found");
    }

    // Parse all files (one file = one card)
    let mut all_cards = Vec::new();
    let mut all_media_files = Vec::new();

    for file in &files {
        dbg!("Reading file", file);
        let content = fs::read_to_string(file)
            .context(format!("Failed to read {}", file.display()))?;

        dbg!("Parsing card from file", file);
        let mut card = parser::parse_card(&content);
        card.file_path = Some(file.to_string_lossy().to_string());

        dbg!("Parsed card", &card.note_type, &card.tags);

        // Extract media file references and resolve paths
        let media_files = parser::extract_media_files(&card, file.parent());
        dbg!("Found media files", &media_files);
        all_media_files.extend(media_files);

        all_cards.push(card);
    }

    // Determine deck name
    let deck_name = args.deck_name.unwrap_or_else(|| {
        if args.input.is_file() {
            // Single file: use parent directory name
            args.input
                .parent()
                .and_then(|p| p.file_name())
                .and_then(|n| n.to_str())
                .unwrap_or("default")
                .to_string()
        } else {
            // Directory: use directory name
            args.input
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("default")
                .to_string()
        }
    });

    dbg!("Deck name", &deck_name);

    // Deduplicate media files
    all_media_files.sort();
    all_media_files.dedup();

    dbg!("Total unique media files", all_media_files.len(), &all_media_files);

    // Generate deck
    dbg!("Generating deck with cards", all_cards.len());
    generator::generate_deck(all_cards, &deck_name, &args.output, all_media_files)?;

    println!("✓ Successfully generated deck: {}", args.output.display());

    Ok(())
}
