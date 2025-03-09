// src/filters.rs
use annotated_text_parser::{Correction, ParsedText};
use html_escape;
use regex::Regex;
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
    Ok(classes.split_whitespace().collect::<Vec<_>>().join(" "))
}

// Format corrections using the annotated_text_parser for parsing
pub fn format_corrections<T: std::fmt::Display>(s: T) -> ::askama::Result<String> {
    let text = s.to_string();

    // Check if the text contains JSON errors
    if text.contains("JSON ERROR:") {
        return Ok(handle_json_errors(&text));
    }

    // Use your parser to parse the XML
    match annotated_text_parser::parse_xml_corrections(&text) {
        Ok(parsed) => {
            // Render the corrections using the new approach
            Ok(render_document_with_corrections(&parsed))
        }
        Err(err) => {
            // Handle parsing errors by returning original text with error message
            Ok(format!(
                "<div class=\"p-3 bg-red-100 text-red-800 rounded mb-4\">Error parsing corrections: {}</div>{}",
                err,
                html_escape::encode_text(&text)
            ))
        }
    }
}

// Handle JSON errors in the text
fn handle_json_errors(text: &str) -> String {
    let re = Regex::new(r"JSON ERROR: ([^<]+)").unwrap();
    let mut result = String::new();
    let mut last_end = 0;

    for cap in re.captures_iter(text) {
        let full_match = cap.get(0).unwrap();
        let start = full_match.start();
        let end = full_match.end();

        // Add text before the error
        if start > last_end {
            result.push_str(&html_escape::encode_text(&text[last_end..start]));
        }

        // Add the error with styling
        result.push_str(&format!(
            "<span class=\"bg-red-200 text-red-800\">{}</span>",
            &text[start..end]
        ));

        last_end = end;
    }

    // Add remaining text
    if last_end < text.len() {
        result.push_str(&html_escape::encode_text(&text[last_end..]));
    }

    result
}

// Entirely new approach to rendering corrections
fn render_document_with_corrections(parsed: &ParsedText) -> String {
    let mut html = String::new();

    // 1. Render the corrected text section with highlighted corrections
    html.push_str("<div class=\"corrected-text mb-6 p-4 bg-white rounded-md border border-gray-200\">");

    // Use a completely different approach for highlighting corrections
    // Instead of trying to manipulate indices, we'll build a map of correction spans
    html.push_str(&render_text_with_highlights(&parsed.corrected_text, &parsed.corrections));

    html.push_str("</div>");

    // 2. Add detailed corrections section
    html.push_str("<div class=\"corrections-details\">");
    html.push_str("<h3 class=\"font-bold text-lg mb-3\">Detailed Corrections</h3>");

    if parsed.corrections.is_empty() {
        html.push_str("<p class=\"text-gray-500 italic\">No corrections needed.</p>");
    } else {
        html.push_str("<ul class=\"space-y-4\">");
        for (i, correction) in parsed.corrections.iter().enumerate() {
            html.push_str(&render_correction_item(correction, i + 1));
        }
        html.push_str("</ul>");
    }

    html.push_str("</div>");

    // 3. Add suggestions section if it exists
    if let Some(suggestions) = &parsed.suggestions {
        html.push_str(&format!(
            "<div class=\"mt-5 p-4 bg-gray-50 rounded-md border-l-4 border-gray-500\">\
            <h3 class=\"font-bold mb-2\">Suggestions for Improvement:</h3>{}</div>",
            html_escape::encode_text(suggestions)
        ));
    }

    html
}

// Render text with highlighted corrections - new safe approach
fn render_text_with_highlights(text: &str, corrections: &[Correction]) -> String {
    // If there are no corrections, just return the escaped text
    if corrections.is_empty() {
        return html_escape::encode_text(text).to_string();
    }

    // Build segments by tokenizing the text
    // This avoids index manipulation errors by working with whole segments
    let mut html = String::new();

    // We'll tokenize the text into words and spaces
    let tokens: Vec<&str> = text.split_inclusive(char::is_whitespace).collect();

    // For each token, check if it contains any correction
    'outer: for token in tokens {
        // Skip empty tokens
        if token.is_empty() {
            continue;
        }

        // Check if this token matches any correction
        for correction in corrections {
            if token.contains(&correction.correction) || correction.correction.contains(token.trim()) {
                // This token contains a correction, highlight it
                let (bg_color, text_color) = get_error_colors(&correction.error_type);

                // Create tooltip content
                let tooltip_content = match &correction.explanation {
                    Some(exp) => format!("{}: {}", correction.original, exp),
                    None => format!("Original: {}", correction.original),
                };

                html.push_str(&format!(
                    "<span class=\"{} {} px-1 rounded relative group cursor-help\" \
                    title=\"{}\">{}<span class=\"absolute hidden group-hover:block \
                    bg-gray-800 text-white text-xs rounded p-2 -mt-16 max-w-xs z-10\">{}</span></span>",
                    bg_color, text_color,
                    html_escape::encode_text(&tooltip_content),
                    html_escape::encode_text(token),
                    html_escape::encode_text(&tooltip_content)
                ));

                continue 'outer;
            }
        }

        // If we get here, this token doesn't match any correction
        html.push_str(&html_escape::encode_text(token));
    }

    html
}

// Render a single correction item in the detailed list
fn render_correction_item(correction: &Correction, index: usize) -> String {
    let (bg_color, text_color) = get_error_colors(&correction.error_type);

    let mut html = String::new();

    html.push_str(&format!(
        "<li class=\"border rounded-lg overflow-hidden\">\
            <div class=\"flex items-center p-3 bg-gray-50 border-b\">\
                <span class=\"font-bold text-gray-700 mr-2\">#{}</span>\
                <span class=\"{} {} px-2 py-1 rounded text-sm font-medium\">{}</span>\
            </div>\
            <div class=\"p-3\">\
                <div class=\"grid grid-cols-1 md:grid-cols-2 gap-3 mb-3\">\
                    <div class=\"p-2 bg-red-50 rounded border border-red-100\">\
                        <div class=\"font-medium mb-1 text-red-800\">Original:</div>\
                        <div>{}</div>\
                    </div>\
                    <div class=\"p-2 bg-green-50 rounded border border-green-100\">\
                        <div class=\"font-medium mb-1 text-green-800\">Correction:</div>\
                        <div>{}</div>\
                    </div>\
                </div>",
        index,
        bg_color, text_color,
        html_escape::encode_text(&correction.error_type),
        html_escape::encode_text(&correction.original),
        html_escape::encode_text(&correction.correction)
    ));

    // Add explanation if present
    if let Some(explanation) = &correction.explanation {
        html.push_str(&format!(
            "<div class=\"p-2 bg-gray-50 rounded border border-gray-200 mb-3\">\
                <div class=\"font-medium mb-1\">Explanation:</div>\
                <div>{}</div>\
            </div>",
            html_escape::encode_text(explanation)
        ));
    }

    // Add nested corrections if any
    if !correction.children.is_empty() {
        html.push_str("<div class=\"mt-2 pl-4 border-l-2 border-gray-300\">");
        html.push_str("<div class=\"font-medium mb-2 text-sm text-gray-600\">Nested Corrections:</div>");
        html.push_str("<ul class=\"space-y-2\">");

        for (i, child) in correction.children.iter().enumerate() {
            html.push_str(&render_nested_correction(child, i + 1));
        }

        html.push_str("</ul></div>");
    }

    html.push_str("</li>");
    html
}

// Render a nested correction item
fn render_nested_correction(correction: &Correction, index: usize) -> String {
    let (bg_color, text_color) = get_error_colors(&correction.error_type);

    let mut html = String::new();

    html.push_str(&format!(
        "<li class=\"border border-gray-200 rounded p-2 bg-white\">\
            <div class=\"flex items-center gap-2 mb-2\">\
                <span class=\"text-xs font-semibold text-gray-500\">#{}.{}</span>\
                <span class=\"{} {} px-1 py-0.5 rounded text-xs font-medium\">{}</span>\
            </div>\
            <div class=\"grid grid-cols-1 gap-2 text-sm\">\
                <div>\
                    <span class=\"font-medium\">Original:</span> {}\
                </div>\
                <div>\
                    <span class=\"font-medium\">Correction:</span> {}\
                </div>",
        index,
        correction.error_type.chars().next().unwrap_or('?'),
        bg_color, text_color,
        html_escape::encode_text(&correction.error_type),
        html_escape::encode_text(&correction.original),
        html_escape::encode_text(&correction.correction)
    ));

    // Add explanation if present
    if let Some(explanation) = &correction.explanation {
        html.push_str(&format!(
            "<div>\
                <span class=\"font-medium\">Explanation:</span> {}\
            </div>",
            html_escape::encode_text(explanation)
        ));
    }

    html.push_str("</div></li>");
    html
}

// Helper function to get colors based on error type
fn get_error_colors(error_type: &str) -> (&'static str, &'static str) {
    match error_type.to_uppercase().as_str() {
        "SPELLING" => ("bg-red-100", "text-red-800"),
        "GRAMMAR" => ("bg-blue-100", "text-blue-800"),
        "PUNCTUATION" => ("bg-purple-100", "text-purple-800"),
        "WORD_CHOICE" => ("bg-orange-100", "text-orange-800"),
        "STYLE" => ("bg-teal-100", "text-teal-800"),
        "STRUCTURAL" => ("bg-green-100", "text-green-800"),
        "COHERENCE" => ("bg-yellow-100", "text-yellow-800"),
        "CAPITALIZATION" => ("bg-indigo-100", "text-indigo-800"),
        "REPETITION" => ("bg-pink-100", "text-pink-800"),
        "FACTUAL" => ("bg-amber-100", "text-amber-800"),
        "FORMATTING" => ("bg-cyan-100", "text-cyan-800"),
        _ => ("bg-gray-100", "text-gray-800"),
    }
}

pub fn length<T: AsRef<str>>(s: T) -> askama::Result<usize> {
    Ok(s.as_ref().len())
}

// Optional alternative for when you need it for Option<String>
pub fn length_opt<T: AsRef<str>>(s: Option<T>) -> askama::Result<usize> {
    match s {
        Some(val) => Ok(val.as_ref().len()),
        None => Ok(0),
    }
}

// For debug purposes - a simple version that just shows the corrected text
#[cfg(debug_assertions)]
pub fn format_corrections_debug<T: std::fmt::Display>(s: T) -> ::askama::Result<String> {
    let text = s.to_string();

    match annotated_text_parser::parse_xml_corrections(&text) {
        Ok(parsed) => {
            // Simple pre-formatted output of the parsed data structure
            Ok(format!(
                "<pre class=\"p-4 bg-gray-100 rounded overflow-auto max-h-96 text-sm\">{:#?}</pre>",
                parsed
            ))
        },
        Err(err) => {
            Ok(format!(
                "<div class=\"p-3 bg-red-100 text-red-800 rounded\">Error: {}</div>",
                err
            ))
        }
    }
}

// Function to render a single correction for test/preview purposes
pub fn preview_correction(
    error_type: &str,
    original: &str,
    correction: &str,
    explanation: Option<&str>,
) -> ::askama::Result<String> {
    let explanation_str = explanation.unwrap_or("");

    let explanation_xml = if explanation_str.is_empty() {
        "".to_string()
    } else {
        format!("<explanation>{}</explanation>", explanation_str)
    };

    let sample_xml = format!(
        "<content>\
            <correction type=\"{}\">\
                <original>{}</original>\
                <corrected>{}</corrected>\
                {}\
            </correction>\
        </content>",
        error_type, original, correction, explanation_xml
    );

    format_corrections(sample_xml)
}
