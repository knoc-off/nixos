mod card;
mod generator;
mod highlighter;
mod parser;

use anyhow::{Context, Result};
use clap::Parser as ClapParser;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

#[derive(ClapParser, Debug)]
#[clap(name = "marki", version, author)]
#[clap(about = "Convert Markdown files to Anki flashcards (.apkg)")]
struct Args {
    input: PathBuf,

    #[clap(short, long, default_value = "output.apkg")]
    output: PathBuf,

    #[clap(short, long)]
    recursive: bool,

    #[clap(short, long)]
    deck_name: Option<String>,
}

fn find_markdown_files(root: &PathBuf, recursive: bool) -> Vec<PathBuf> {
    // dbg!("Finding markdown files", root, recursive);

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

    // dbg!("Found markdown files", files.len());
    // for file in &files {
    //     dbg!("  -", file);
    // }

    files
}

fn deck_name_from_dir(input: &Path, file: &Path) -> String {
    if input.is_file() {
        return file
            .parent()
            .and_then(|p| p.file_name())
            .and_then(|n| n.to_str())
            .unwrap_or("default")
            .to_string();
    }

    let base_name = input
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("default");

    let subdirs: Vec<_> = file
        .strip_prefix(input)
        .ok()
        .and_then(|p| p.parent())
        .into_iter()
        .flat_map(|p| p.components())
        .filter_map(|c| match c {
            std::path::Component::Normal(s) => s.to_str(),
            _ => None,
        })
        .collect();

    if subdirs.is_empty() {
        base_name.to_string()
    } else {
        format!("{}::{}", base_name, subdirs.join("::"))
    }
}

fn main() -> Result<()> {
    let args = Args::parse();

    // dbg!(&args);

    // Determine if input is file or directory
    let files = if args.input.is_file() {
        // dbg!("Input is a file");
        vec![args.input.clone()]
    } else if args.input.is_dir() {
        // dbg!("Input is a directory");
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
        let content =
            fs::read_to_string(file).context(format!("Failed to read {}", file.display()))?;

        let mut card = parser::parse_card(&content);
        card.file_path = Some(file.to_string_lossy().to_string());

        card.deck_name = deck_name_from_dir(&args.input, file);
        // dbg!("Card deck name", &card.deck_name);

        // dbg!("Parsed card", &card.note_type, &card.tags);

        let media_files = parser::extract_media_files(&card, file.parent());
        // dbg!("Found media files", &media_files);
        all_media_files.extend(media_files);

        all_cards.push(card);
    }

    let mut decks: HashMap<String, Vec<card::Card>> = HashMap::new();
    for card in all_cards {
        decks.entry(card.deck_name.clone()).or_default().push(card);
    }

    dbg!("Total decks", decks.len());
    for (deck_name, cards) in &decks {
        dbg!("Deck", deck_name, cards.len());
    }

    all_media_files.sort();
    all_media_files.dedup();

    dbg!(
        "Total unique media files",
        all_media_files.len(),
        &all_media_files
    );

    // dbg!("Generating decks");
    generator::generate_decks(decks, &args.output, all_media_files)?;

    println!("Successfully generated deck: {}", args.output.display());

    Ok(())
}
