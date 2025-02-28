// src/filters.rs
use annotated_text_parser::{parse_corrections, ParsedText, Correction};
use std::fs;
use std::path::PathBuf;
use html_escape;

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
    Ok(classes.split_whitespace().collect::<Vec<_>>().join(" "))
}

// Format corrections using the annotated_text_parser for parsing
pub fn format_corrections<T: std::fmt::Display>(s: T) -> ::askama::Result<String> {
    let text = s.to_string();

    match parse_corrections(&text) {
        Ok(parsed) => {
            let html = render_html(&parsed);
            Ok(html)
        },
        Err(err) => {
            // Handle parsing errors by returning original text with error message
            Ok(format!(
                "<div class='p-2 bg-red-100 text-red-800 rounded mb-4'>Error parsing corrections: {}</div>{}",
                err,
                html_escape::encode_text(&text)
            ))
        }
    }
}

// Main function to render the parsed text as HTML
fn render_html(parsed: &ParsedText) -> String {
    // Use the corrected text as the base
    let mut html = String::new();

    // Map each correction to its span in the document
    let spans = build_correction_spans(parsed);

    // Build the HTML with the formatted spans
    html.push_str(&spans);

    // Add suggestions section if it exists
    if let Some(suggestions_text) = &parsed.suggestions {
        html.push_str(&format!(
            "<div class=\"mt-5 p-4 bg-gray-50 rounded-md border-l-4 border-gray-500\"><h3 class=\"font-bold mb-2\">Suggestions for Improvement:</h3>{}</div>",
            suggestions_text
        ));
    }

    html
}

// Build HTML with correction spans
fn build_correction_spans(parsed: &ParsedText) -> String {
    if parsed.corrections.is_empty() {
        // If no corrections, just return the text
        return parsed.text.clone();
    }

    // We'll use a recursive approach to handle nested corrections
    format_with_corrections(&parsed.text, &parsed.corrections)
}

fn format_with_corrections(text: &str, corrections: &[Correction]) -> String {
    // Handle all corrections at this level
    let mut formatted_text = text.to_string();

    for correction in corrections {
        // Create the HTML span for this correction
        let span = create_correction_span(correction);

        // Replace the corrected text with the HTML span
        formatted_text = formatted_text.replace(&correction.correction, &span);
    }

    formatted_text
}

fn create_correction_span(correction: &Correction) -> String {
    // Map error types to colors
    let color = match correction.error_type.as_str() {
        "TYPO" => "red",
        "GRAM" => "blue",
        "PUNC" => "purple",
        "WORD" => "orange",
        "STYL" => "teal",
        "STRUC" => "green",
        _ => "gray",
    };

    // Build tooltip content
    let mut tooltip = correction.original.clone();

    // Include explanation if available
    if let Some(explanation) = &correction.explanation {
        tooltip = format!("{}: {}", tooltip, explanation);
    }

    // Escape HTML in the tooltip
    let escaped_tooltip = html_escape::encode_text(&tooltip);

    // Format nested children first if any
    let display_text = if !correction.children.is_empty() {
        format_with_corrections(&correction.correction, &correction.children)
    } else {
        html_escape::encode_text(&correction.correction).into_owned()
    };

    format!(
        r#"<span class="bg-{}-100 text-{}-800 px-1 rounded-sm cursor-help" title="{}" data-error-type="{}">{}</span>"#,
        color, color, escaped_tooltip, correction.error_type, display_text
    )
}

// Debug version that shows additional information
#[cfg(debug_assertions)]
pub fn format_corrections_debug<T: std::fmt::Display>(s: T) -> ::askama::Result<String> {
    let text = s.to_string();

    match annotated_text_parser::parse_corrections_debug(&text) {
        Ok(parsed) => {
            // Get the standard HTML output
            let html = render_html(&parsed);

            // Add debugging information
            let debug_html = format!(
                "{}<div class='mt-4 p-4 bg-gray-100 border border-gray-300 rounded'>\
                <h3 class='font-bold mb-2'>Debug Information</h3>\
                <div class='text-xs font-mono whitespace-pre-wrap overflow-auto max-h-96'>\
                <p>Total corrections: {}</p>\
                <p>Parsed structure:</p>\
                <pre>{:#?}</pre>\
                </div></div>",
                html,
                parsed.corrections.len(),
                parsed.corrections
            );

            Ok(debug_html)
        },
        Err(err) => {
            // Detailed error for debugging
            Ok(format!(
                "<div class='p-4 bg-red-100 border border-red-300 text-red-800 rounded mb-4'>\
                <h3 class='font-bold'>Parsing Error</h3>\
                <p class='mb-2'>{}</p>\
                <div class='text-xs font-mono bg-white p-2 rounded border border-red-200 whitespace-pre-wrap'>{}</div>\
                </div>",
                err,
                html_escape::encode_text(&text)
            ))
        }
    }
}

// Function to render a single correction for test/preview purposes
pub fn preview_correction(error_type: &str, original: &str, correction: &str, explanation: Option<&str>) -> ::askama::Result<String> {
    let explanation_str = explanation.unwrap_or("");

    let sample_text = format!(
        "[{}{{{}|{}{}}}]",
        error_type,
        original,
        correction,
        if explanation_str.is_empty() { "".to_string() } else { format!("|{}", explanation_str) }
    );

    format_corrections(sample_text)
}

