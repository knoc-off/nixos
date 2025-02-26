use std::fs;
use std::path::PathBuf;

// Load SVG file from static directory
pub fn icon(name: &str) -> askama::Result<String> {
    let icon_path = PathBuf::from("static/icons").join(format!("{}.svg", name));

    match fs::read_to_string(&icon_path) {
        Ok(content) => Ok(content),
        Err(_) => Ok(format!("<!-- Icon '{}' not found -->", name)),
    }
}

// Create a simple class concatenation filter
pub fn class(classes: &str) -> askama::Result<String> {
    Ok(classes
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" "))
}

