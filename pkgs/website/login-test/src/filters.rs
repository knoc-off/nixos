// src/filters.rs
use annotated_text_parser::{XmlParser, ParsedText, TextSegment};
use std::fs;
use std::path::PathBuf;
use html_escape;
use regex::Regex;

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

    match parse_corrections(&text) {
        Ok(parsed) => {
            // Render the corrections using the new segment-based approach
            let html = render_corrections_with_segments(&parsed);
            Ok(html)
        },
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

// Render corrections using the new segment-based approach
fn render_corrections_with_segments(parsed: &ParsedText) -> String {
    let mut html = String::new();

    // Render the corrected text as a paragraph with inline highlighted corrections
    html.push_str("<div class=\"corrected-text mb-6 p-4 bg-white rounded-md border border-gray-200\">");
    html.push_str(&render_segments_inline(&parsed.segments));
    html.push_str("</div>");

    // Add detailed corrections section
    html.push_str("<div class=\"corrections-details\">");
    html.push_str("<h3 class=\"font-bold text-lg mb-3\">Detailed Corrections</h3>");
    html.push_str(&render_segments_detailed(&parsed.segments));
    html.push_str("</div>");

    // Add suggestions section if it exists
    if let Some(suggestions) = &parsed.suggestions {
        html.push_str(&format!(
            "<div class=\"mt-5 p-4 bg-gray-50 rounded-md border-l-4 border-gray-500\">\
            <h3 class=\"font-bold mb-2\">Suggestions for Improvement:</h3>{}</div>",
            suggestions
        ));
    }

    html
}

// Render segments as inline text with highlighted corrections
fn render_segments_inline(segments: &[TextSegment]) -> String {
    let mut html = String::new();

    for segment in segments {
        match segment {
            TextSegment::Plain(text) => {
                html.push_str(&html_escape::encode_text(text));
            },
            TextSegment::Correction { error_type, original, correction, explanation, children, .. } => {
                // If there are children, render them recursively
                if !children.is_empty() {
                    html.push_str(&render_segments_inline(children));
                } else {
                    // Map error types to colors for highlighting
                    let (bg_color, text_color) = get_error_colors(error_type);

                    // Create tooltip content
                    let tooltip_content = match explanation {
                        Some(exp) => format!("{}: {}", original, exp),
                        None => format!("Original: {}", original),
                    };

                    // Render the correction with highlighting and tooltip
                    html.push_str(&format!(
                        "<span class=\"{} {} px-1 rounded relative group cursor-help\" \
                        title=\"{}\">{}<span class=\"absolute hidden group-hover:block \
                        bg-gray-800 text-white text-xs rounded p-2 -mt-16 max-w-xs z-10\">{}</span></span>",
                        bg_color, text_color,
                        html_escape::encode_text(&tooltip_content),
                        html_escape::encode_text(correction),
                        html_escape::encode_text(&tooltip_content)
                    ));
                }
            }
        }
    }

    html
}

// Render detailed view of corrections
fn render_segments_detailed(segments: &[TextSegment]) -> String {
    let mut html = String::new();
    let mut correction_index = 1;

    for segment in segments {
        match segment {
            TextSegment::Plain(_) => {
                // Skip plain text in detailed view
            },
            TextSegment::Correction { error_type, original, correction, explanation, children, .. } => {
                // If there are children, include them in the detailed view
                if !children.is_empty() {
                    html.push_str(&render_segments_detailed(children));
                } else {
                    // Map error types to colors
                    let (bg_color, text_color) = get_error_colors(error_type);

                    // Format the correction detail
                    html.push_str(&format!(
                        "<div class=\"mb-4 p-3 border rounded\">\
                            <div class=\"flex items-center gap-2 mb-2\">\
                                <span class=\"font-bold text-gray-700\">#{}</span>\
                                <span class=\"{} {} px-2 py-1 rounded text-sm font-medium\">{}</span>\
                            </div>\
                            <div class=\"grid grid-cols-1 md:grid-cols-2 gap-3\">\
                                <div class=\"p-2 bg-red-50 rounded\">\
                                    <div class=\"font-medium mb-1\">Original:</div>\
                                    <div>{}</div>\
                                </div>\
                                <div class=\"p-2 bg-green-50 rounded\">\
                                    <div class=\"font-medium mb-1\">Correction:</div>\
                                    <div>{}</div>\
                                </div>\
                            </div>\
                            {}
                        </div>",
                        correction_index,
                        bg_color, text_color, error_type,
                        html_escape::encode_text(original),
                        html_escape::encode_text(correction),
                        if let Some(exp) = explanation {
                            format!("<div class=\"mt-2 p-2 bg-gray-50 rounded\">\
                                <div class=\"font-medium mb-1\">Explanation:</div>\
                                <div>{}</div>\
                            </div>", html_escape::encode_text(exp))
                        } else {
                            String::new()
                        }
                    ));

                    correction_index += 1;
                }
            }
        }
    }

    html
}

// Helper function to get colors based on error type
fn get_error_colors(error_type: &str) -> (&'static str, &'static str) {
    match error_type {
        "TYPO" => ("bg-red-100", "text-red-800"),
        "GRAM" => ("bg-blue-100", "text-blue-800"),
        "PUNC" => ("bg-purple-100", "text-purple-800"),
        "WORD" => ("bg-orange-100", "text-orange-800"),
        "STYL" => ("bg-teal-100", "text-teal-800"),
        "STRUC" => ("bg-green-100", "text-green-800"),
        _ => ("bg-gray-100", "text-gray-800"),
    }
}

// Debug version that shows additional information
#[cfg(debug_assertions)]
pub fn format_corrections_debug<T: std::fmt::Display>(s: T) -> ::askama::Result<String> {
    let text = s.to_string();

    match parse_corrections(&text) {
        Ok(parsed) => {
            // Get the standard HTML output
            let html = render_corrections_with_segments(&parsed);

            // Add debugging information
            let debug_html = format!(
                "{}<div class='mt-4 p-4 bg-gray-100 border border-gray-300 rounded'>\
                <h3 class='font-bold mb-2'>Debug Information</h3>\
                <div class='text-xs font-mono whitespace-pre-wrap overflow-auto max-h-96'>\
                <p>Total segments: {}</p>\
                <p>Parsed structure:</p>\
                <pre>{:#?}</pre>\
                </div></div>",
                html,
                parsed.segments.len(),
                parsed.segments
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

