use clap::Parser as ClapParser; // Alias to avoid conflict with tree_sitter::Parser
use std::fs;
use tree_sitter::{Language, Node, Parser, TreeCursor};

// --- Language Configuration ---
// You need to explicitly link the language grammar.
// Change this line based on the language you want to parse.
extern "C" {
    fn tree_sitter_rust() -> Language;
    // Example for Python:
    // fn tree_sitter_python() -> Language;
    // Example for JavaScript:
    // fn tree_sitter_javascript() -> Language;
}

// --- Command Line Arguments ---
#[derive(ClapParser, Debug)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// The source code file to analyze
    #[arg(value_name = "FILE_PATH")]
    file_path: String,

    /// Optional: Show node kinds for debugging
    #[arg(short, long)]
    debug_kinds: bool,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    // --- Read File ---
    let source_code = fs::read_to_string(&cli.file_path)?;
    println!("--- Overview for: {} ---", cli.file_path);

    // --- Setup Parser ---
    let mut parser = Parser::new();

    // Set the language (change function name for other languages)
    let language = unsafe { tree_sitter_rust() };
    // Example for Python:
    // let language = unsafe { tree_sitter_python() };
    parser
        .set_language(&language)
        .expect("Error loading grammar");

    // --- Parse ---
    let tree = parser
        .parse(&source_code, None) // None means parse from scratch
        .expect("Error parsing file");

    let root_node = tree.root_node();

    // --- Traverse and Extract ---
    let mut cursor = root_node.walk();
    walk_tree(&source_code, &mut cursor, 0, cli.debug_kinds);

    println!("\n--- End Overview ---");
    Ok(())
}

// Recursive function to walk the syntax tree
fn walk_tree(
    source_code: &str,
    cursor: &mut TreeCursor,
    depth: usize,
    debug_kinds: bool,
) {
    let node = cursor.node();
    let kind = node.kind();
    let start = node.start_position();
    let line = start.row + 1; // Line numbers are 0-based

    // --- Print Node Kind (Optional Debugging) ---
    if debug_kinds {
        let indent = "  ".repeat(depth);
        println!(
            "{}Kind: '{}', Line: {}",
            indent,
            kind,
            line
        );
    }

    // --- Extract Specific Declarations (Customize based on language) ---
    match kind {
        // --- Rust Specific Kinds ---
        "function_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                println!("L{:<4} Function: {}", line, name);
            }
        }
        "struct_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                println!("L{:<4} Struct:   {}", line, name);
            }
        }
        "enum_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                println!("L{:<4} Enum:     {}", line, name);
            }
        }
        "impl_item" => {
            let mut type_name = "[Unknown Type]".to_string();
            let mut trait_name = "".to_string();

            if let Some(type_node) = node.child_by_field_name("type") {
                type_name = get_node_text(type_node, source_code).trim().to_string();
            }
            if let Some(trait_node) = node.child_by_field_name("trait") {
                 trait_name = format!(" for {}", get_node_text(trait_node, source_code).trim());
            }

            println!("L{:<4} Impl:     {}{}", line, type_name, trait_name);
            // Recurse specifically into impl blocks to find methods
            process_children(source_code, cursor, depth, debug_kinds);
            return; // Avoid double processing children
        }
        "trait_item" => {
            if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                println!("L{:<4} Trait:    {}", line, name);
            }
        }
        "const_item" | "static_item" => {
             if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                let item_type = if kind == "const_item" { "Const" } else { "Static" };
                println!("L{:<4} {}: {}", line, item_type, name);
            }
        }
        "mod_item" => {
             if let Some(name_node) = node.child_by_field_name("name") {
                let name = get_node_text(name_node, source_code);
                println!("L{:<4} Module:   {}", line, name);
                 // Recurse specifically into mod blocks
                process_children(source_code, cursor, depth, debug_kinds);
                return; // Avoid double processing children
            }
        }
        // --- Add more kinds for Rust or other languages ---
        // Example for Python: "function_definition", "class_definition"
        // Example for JS: "function_declaration", "class_declaration", "lexical_declaration" (for const/let)

        // --- Default: Recurse into children ---
        // Only recurse if we haven't specifically handled recursion above (like for impl/mod)
        _ => {
             process_children(source_code, cursor, depth, debug_kinds);
        }
    }
}

// Helper function to process children of the current node
fn process_children(
    source_code: &str,
    cursor: &mut TreeCursor,
    depth: usize,
    debug_kinds: bool,
) {
     if cursor.goto_first_child() {
        loop {
            walk_tree(source_code, cursor, depth + 1, debug_kinds);
            if !cursor.goto_next_sibling() {
                break;
            }
        }
        cursor.goto_parent(); // Go back up after processing children
    }
}


// Helper function to get the text content of a node
fn get_node_text<'a>(node: Node<'a>, source: &'a str) -> &'a str {
    node.utf8_text(source.as_bytes()).unwrap_or("[Error reading text]")
}

