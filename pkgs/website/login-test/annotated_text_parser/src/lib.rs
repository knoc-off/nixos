use std::usize;

// lib.rs
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Correction {
    pub error_type: String,
    pub original: String,
    pub correction: String,
    pub explanation: Option<String>,
    pub children: Vec<Correction>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub enum TextSegment {
    Plain(String),
    Correction {
        error_type: String,
        original: String,
        correction: String,
        explanation: Option<String>,
        children: Vec<TextSegment>,
        // Store the original and corrected versions of this segment
        original_segments: Vec<TextSegment>,
        corrected_segments: Vec<TextSegment>,
    },
}

impl TextSegment {
    // Helper method to get the original text from a segment
    pub fn get_original_text(&self) -> String {
        match self {
            TextSegment::Plain(text) => text.clone(),
            TextSegment::Correction { original, .. } => original.clone(),
        }
    }

    // Helper method to get the corrected text from a segment
    pub fn get_corrected_text(&self) -> String {
        match self {
            TextSegment::Plain(text) => text.clone(),
            TextSegment::Correction { correction, .. } => correction.clone(),
        }
    }
}

#[derive(Debug, Error)]
pub enum ParserError {
    #[error("Invalid error type: {0}")]
    InvalidErrorType(String),

    #[error("Unexpected end of input at position {0}")]
    UnexpectedEndOfInput(usize),

    #[error("Missing closing bracket at position {0}")]
    MissingClosingBracket(usize),

    #[error("Missing closing brace at position {0}")]
    MissingClosingBrace(usize),

    #[error("Missing pipe separator at position {0}")]
    MissingPipeSeparator(usize),

    #[error("JSON serialization error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("excessive recursion at position {0}")]
    RecursiveError(String),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ParsedText {
    pub text: String,
    pub corrections: Vec<Correction>,
    pub suggestions: Option<String>,
    pub segments: Vec<TextSegment>, // New field for the segmented text
}

pub struct Parser {
    debug_mode: bool,
}

impl Parser {
    pub fn new() -> Self {
        Self { debug_mode: false }
    }

    pub fn with_debug(mut self, debug: bool) -> Self {
        self.debug_mode = debug;
        self
    }

    pub fn parse(&self, text: &str) -> Result<ParsedText, ParserError> {
        // Split suggestions section if it exists
        let parts: Vec<&str> = text.split("[SUGGESTIONS]").collect();
        let main_text = parts[0].trim();
        let suggestions = if parts.len() > 1 {
            Some(parts[1].trim().to_string())
        } else {
            None
        };

        // Parse the main text with corrections
        let (parsed_text, corrections, segments) = self.parse_nested_corrections(main_text)?;

        Ok(ParsedText {
            text: parsed_text,
            corrections,
            suggestions,
            segments,
        })
    }

    // Modify the parse_nested_corrections method to handle adjacent corrections and build segments
    fn parse_nested_corrections(
        &self,
        text: &str,
    ) -> Result<(String, Vec<Correction>, Vec<TextSegment>), ParserError> {
        let mut result = String::new();
        let mut corrections = Vec::new();
        let mut segments = Vec::new();
        let mut current_pos = 0;
        let mut plain_text_start = 0;
        let text_chars: Vec<char> = text.chars().collect();

        while current_pos < text_chars.len() {
            if current_pos + 1 < text_chars.len() && text_chars[current_pos] == '[' {
                // This might be the start of a correction
                match self.try_parse_correction(&text_chars, current_pos, 0) {
                    Ok((Some(parsed), new_pos, segment)) => {
                        if self.debug_mode {
                            println!("Successfully parsed correction: {:?}", parsed);
                        }

                        // If there's plain text before this correction, add it as a segment
                        if current_pos > plain_text_start {
                            let plain_text: String =
                                text_chars[plain_text_start..current_pos].iter().collect();
                            if !plain_text.is_empty() {
                                segments.push(TextSegment::Plain(plain_text));
                            }
                        }

                        // Add the correction to our list
                        corrections.push(parsed);

                        // Add the correction segment
                        segments.push(segment);

                        // Add the corrected text to the result
                        result.push_str(&corrections.last().unwrap().correction);
                        current_pos = new_pos;
                        plain_text_start = current_pos;
                    }
                    Ok((None, new_pos, _)) => {
                        // Not a correction, just a regular character
                        result.push(text_chars[current_pos]);
                        current_pos = new_pos;
                    }
                    Err(e) => {
                        if self.debug_mode {
                            println!("Error parsing at position {}: {}", current_pos, e);
                        }
                        // On error, just treat as regular text and continue
                        result.push(text_chars[current_pos]);
                        current_pos += 1;
                    }
                }
            } else {
                // Regular character
                result.push(text_chars[current_pos]);
                current_pos += 1;
            }
        }

        // Add any remaining plain text
        if current_pos > plain_text_start {
            let plain_text: String = text_chars[plain_text_start..current_pos].iter().collect();
            if !plain_text.is_empty() {
                segments.push(TextSegment::Plain(plain_text));
            }
        }

        Ok((result, corrections, segments))
    }

    // Modify the try_parse_correction method to build the segment structure
    fn try_parse_correction(
        &self,
        chars: &[char],
        start_pos: usize,
        depth: usize,
    ) -> Result<(Option<Correction>, usize, TextSegment), ParserError> {
        // Check recursion depth
        if depth > 100 {
            // Set a reasonable maximum
            return Err(ParserError::RecursiveError(start_pos.to_string()));
        }
        // Check if this is the start of a correction
        if chars[start_pos] != '[' {
            let segment = TextSegment::Plain(chars[start_pos].to_string());
            return Ok((None, start_pos + 1, segment));
        }

        if self.debug_mode {
            println!("Attempting to parse correction at position {}", start_pos);
            // Print the next few characters for context
            let context: String = chars.iter().skip(start_pos).take(20).collect();
            println!("Context: {}", context);
        }

        // Find the error type
        let mut pos = start_pos + 1;
        let mut error_type = String::new();

        while pos < chars.len() && chars[pos] != '{' {
            error_type.push(chars[pos]);
            pos += 1;
        }

        // Validate error type
        let error_type = error_type.trim();
        if !["TYPO", "GRAM", "PUNC", "WORD", "STYL", "STRUC"].contains(&error_type) {
            if self.debug_mode {
                println!(
                    "Invalid error type: {} at position {}",
                    error_type, start_pos
                );
            }
            let segment =
                TextSegment::Plain(chars[start_pos..start_pos + 1].iter().collect::<String>());
            return Ok((None, start_pos + 1, segment));
        }

        // Parse the content inside the curly braces
        if pos >= chars.len() {
            return Err(ParserError::UnexpectedEndOfInput(pos));
        }

        if chars[pos] != '{' {
            if self.debug_mode {
                println!("Expected '{{' at position {}, found '{}'", pos, chars[pos]);
            }
            let segment =
                TextSegment::Plain(chars[start_pos..start_pos + 1].iter().collect::<String>());
            return Ok((None, start_pos + 1, segment));
        }

        pos += 1; // Skip the opening curly brace

        // Check for double braces ({{) and skip the second one if present
        if pos < chars.len() && chars[pos] == '{' {
            // TODO this is a hack
            pos += 1; // Skip the second opening brace
        }

        let mut original = String::new();
        let mut correction = String::new();
        let mut explanation = String::new();
        let mut children = Vec::new();
        let mut child_segments = Vec::new();

        // Parse the original text (which may contain nested corrections)
        let mut brace_count = 1;
        let mut in_original = true;
        let mut in_correction = false;
        let mut in_explanation = false;

        let _original_start_pos = pos; // Prefix with underscore to avoid warning
        let mut original_text_buffer = String::new();
        let mut original_segments = Vec::new();
        let mut corrected_segments = Vec::new();

        while pos < chars.len() && !(chars[pos] == '}' && brace_count == 1) {
            if in_original {
                if pos + 1 < chars.len() && chars[pos] == '[' {
                    // Check if this is a nested correction or just a bracket in the content
                    let _potential_correction_start = pos;
                    let mut potential_error_type = String::new();
                    let mut i = pos + 1;

                    // Try to extract a potential error type
                    while i < chars.len() && chars[i] != '{' && chars[i] != ']' && i - pos - 1 < 10
                    {
                        potential_error_type.push(chars[i]);
                        i += 1;
                    }

                    // Check if it's a valid error type followed by a '{'
                    if i < chars.len()
                        && chars[i] == '{'
                        && ["TYPO", "GRAM", "PUNC", "WORD", "STYL", "STRUC"]
                            .contains(&potential_error_type.trim())
                    {
                        // This is likely a nested correction
                        // First, add any accumulated text before this nested correction
                        if !original_text_buffer.is_empty() {
                            original_segments
                                .push(TextSegment::Plain(original_text_buffer.clone()));
                            original_text_buffer.clear();
                        }

                        match self.try_parse_correction(chars, pos, depth + 1) {
                            Ok((Some(nested), new_pos, segment)) => {
                                children.push(nested.clone());
                                child_segments.push(segment.clone());

                                // Add the nested correction's original text to our original
                                original.push_str(&nested.original);

                                // Add the segment to our original segments
                                original_segments.push(segment);

                                pos = new_pos;
                                continue;
                            }
                            Ok((None, _, _)) => {
                                // Not a nested correction, treat as regular character
                                original.push(chars[pos]);
                                original_text_buffer.push(chars[pos]);
                            }
                            Err(e) => {
                                if self.debug_mode {
                                    println!("Error parsing nested correction: {}", e);
                                }
                                // On error, just treat as regular text
                                original.push(chars[pos]);
                                original_text_buffer.push(chars[pos]);
                            }
                        }
                    } else {
                        // Just a regular bracket in the content
                        original.push(chars[pos]);
                        original_text_buffer.push(chars[pos]);
                    }
                } else if chars[pos] == '|' && brace_count == 1 {
                    // Add any remaining text in the original buffer
                    if !original_text_buffer.is_empty() {
                        original_segments.push(TextSegment::Plain(original_text_buffer.clone()));
                        original_text_buffer.clear();
                    }

                    in_original = false;
                    in_correction = true;
                    pos += 1;
                    continue;
                } else {
                    if chars[pos] == '{' {
                        brace_count += 1;
                    } else if chars[pos] == '}' {
                        brace_count -= 1;
                    }
                    original.push(chars[pos]);
                    original_text_buffer.push(chars[pos]);
                }
            } else if in_correction {
                if chars[pos] == '|' && brace_count == 1 {
                    in_correction = false;
                    in_explanation = true;
                    pos += 1;
                    continue;
                } else {
                    if chars[pos] == '{' {
                        brace_count += 1;
                    } else if chars[pos] == '}' {
                        brace_count -= 1;
                    }
                    correction.push(chars[pos]);
                }
            } else if in_explanation {
                if chars[pos] == '{' {
                    brace_count += 1;
                } else if chars[pos] == '}' {
                    brace_count -= 1;
                }
                explanation.push(chars[pos]);
            }

            pos += 1;

            if pos >= chars.len() && brace_count > 0 {
                return Err(ParserError::MissingClosingBrace(pos));
            }
        }

        // Add any remaining text in the original buffer
        if !original_text_buffer.is_empty() {
            original_segments.push(TextSegment::Plain(original_text_buffer));
        }

        // Add the correction as a plain text segment
        if !correction.is_empty() {
            corrected_segments.push(TextSegment::Plain(correction.clone()));
        } else if !child_segments.is_empty() {
            // If there are child segments but no explicit correction text,
            // use the corrected versions of the child segments
            for child in &child_segments {
                match child {
                    TextSegment::Plain(text) => {
                        corrected_segments.push(TextSegment::Plain(text.clone()));
                    }
                    TextSegment::Correction { correction, .. } => {
                        corrected_segments.push(TextSegment::Plain(correction.clone()));
                    }
                }
            }
        }

        // Skip the closing curly brace
        if pos < chars.len() && chars[pos] == '}' {
            pos += 1;
            // Skip second closing brace if present (for }})
            if pos < chars.len() && chars[pos] == '}' {
                // TODO This is a hack, should just
                // validate the input
                pos += 1;
            }
        } else {
                        return Err(ParserError::MissingClosingBrace(pos));
        }

        // Skip the closing bracket
        if pos < chars.len() && chars[pos] == ']' {
            pos += 1;
        } else {
            return Err(ParserError::MissingClosingBracket(pos));
        }

        // Validate that we have both original and correction
        if original.is_empty() && correction.is_empty() {
            if self.debug_mode {
                println!("Missing original or correction at position {}", start_pos);
            }
            let segment =
                TextSegment::Plain(chars[start_pos..start_pos + 1].iter().collect::<String>());
            return Ok((None, start_pos + 1, segment));
        }

        let explanation = if explanation.is_empty() {
            None
        } else {
            Some(explanation)
        };

        // Fix: Normalize spaces in original text for nested corrections
        let original = self.normalize_spaces(&original);

        let correction_obj = Correction {
            error_type: error_type.to_string(),
            original: original.clone(),
            correction: correction.clone(),
            explanation: explanation.clone(),
            children,
        };

        // If we don't have any original segments but have original text,
        // create a plain text segment for it
        if original_segments.is_empty() && !correction_obj.original.is_empty() {
            original_segments.push(TextSegment::Plain(correction_obj.original.clone()));
        }

        // If we don't have any corrected segments but have correction text,
        // create a plain text segment for it
        if corrected_segments.is_empty() && !correction_obj.correction.is_empty() {
            corrected_segments.push(TextSegment::Plain(correction_obj.correction.clone()));
        }

        let segment = TextSegment::Correction {
            error_type: error_type.to_string(),
            original: original.clone(),
            correction: correction_obj.correction.clone(),
            explanation: explanation.clone(),
            children: child_segments,
            original_segments,
            corrected_segments,
        };

        Ok((Some(correction_obj), pos, segment))
    }

    // Helper method to normalize spaces in text
    fn normalize_spaces(&self, text: &str) -> String {
        // Replace multiple spaces with a single space
        let mut result = String::new();
        let mut last_was_space = false;

        for c in text.chars() {
            if c == ' ' {
                if !last_was_space {
                    result.push(c);
                }
                last_was_space = true;
            } else {
                result.push(c);
                last_was_space = false;
            }
        }

        result
    }

    // Helper method to reconstruct the original text from segments
    pub fn reconstruct_original(&self, segments: &[TextSegment]) -> String {
        let mut result = String::new();
        for segment in segments {
            match segment {
                TextSegment::Plain(text) => {
                    result.push_str(text);
                }
                TextSegment::Correction { original, .. } => {
                    result.push_str(original);
                }
            }
        }
        result
    }

    // Helper method to reconstruct the corrected text from segments
    pub fn reconstruct_corrected(&self, segments: &[TextSegment]) -> String {
        let mut result = String::new();
        for segment in segments {
            match segment {
                TextSegment::Plain(text) => {
                    result.push_str(text);
                }
                TextSegment::Correction { correction, .. } => {
                    result.push_str(correction);
                }
            }
        }
        result
    }
}

// Convenience function for simple usage
pub fn parse_corrections(text: &str) -> Result<ParsedText, ParserError> {
    let parser = Parser::new();
    parser.parse(text)
}

// Convenience function with debug mode
pub fn parse_corrections_debug(text: &str) -> Result<ParsedText, ParserError> {
    let parser = Parser::new().with_debug(true);
    parser.parse(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_correction() {
        let input = "This has a [TYPO{mispeling|misspelling}] in it.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "misspelling");

        // Test segments
        assert_eq!(result.segments.len(), 3);
        match &result.segments[0] {
            TextSegment::Plain(text) => assert_eq!(text, "This has a "),
            _ => panic!("Expected Plain segment"),
        }
        match &result.segments[1] {
            TextSegment::Correction {
                error_type,
                original,
                correction,
                ..
            } => {
                assert_eq!(error_type, "TYPO");
                assert_eq!(original, "mispeling");
                assert_eq!(correction, "misspelling");
            }
            _ => panic!("Expected Correction segment"),
        }
        match &result.segments[2] {
            TextSegment::Plain(text) => assert_eq!(text, " in it."),
            _ => panic!("Expected Plain segment"),
        }

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This has a mispeling in it.");
        assert_eq!(corrected, "This has a misspelling in it.");
    }

    #[test]
    fn test_nested_correction() {
        let input = "[STYL{This sentence has [GRAM{a error|an error}] in it.|This sentence has an error in it.}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STYL");
        assert_eq!(result.corrections[0].children.len(), 1);
        assert_eq!(result.corrections[0].children[0].error_type, "GRAM");
        assert_eq!(result.corrections[0].children[0].original, "a error");
        assert_eq!(result.corrections[0].children[0].correction, "an error");

        // Test segments
        assert_eq!(result.segments.len(), 1);
        match &result.segments[0] {
            TextSegment::Correction {
                error_type,
                children,
                original,
                ..
            } => {
                assert_eq!(error_type, "STYL");
                assert_eq!(children.len(), 1);
                assert_eq!(original, "This sentence has a error in it.");
                match &children[0] {
                    TextSegment::Correction {
                        error_type,
                        original,
                        correction,
                        ..
                    } => {
                        assert_eq!(error_type, "GRAM");
                        assert_eq!(original, "a error");
                        assert_eq!(correction, "an error");
                    }
                    _ => panic!("Expected nested Correction segment"),
                }
            }
            _ => panic!("Expected Correction segment"),
        }

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This sentence has a error in it.");
        assert_eq!(corrected, "This sentence has an error in it.");
    }

    #[test]
    fn test_with_suggestions() {
        let input = "This is a test.\n\n[SUGGESTIONS]\nHere are some suggestions.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.text, "This is a test.");
        assert_eq!(
            result.suggestions,
            Some("Here are some suggestions.".to_string())
        );

        // Test segments
        assert_eq!(result.segments.len(), 1);
        match &result.segments[0] {
            TextSegment::Plain(text) => assert_eq!(text, "This is a test."),
            _ => panic!("Expected Plain segment"),
        }
    }

    #[test]
    fn test_multiple_corrections() {
        let input = "This [TYPO{sentance|sentence}] has [GRAM{many error|many errors}].";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 2);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "sentance");
        assert_eq!(result.corrections[1].error_type, "GRAM");
        assert_eq!(result.corrections[1].correction, "many errors");

        // Test segments
        assert_eq!(result.segments.len(), 4);

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This sentance has many error.");
        assert_eq!(corrected, "This sentence has many errors.");
    }

    #[test]
    fn test_complex_nested_correction() {
        let input = "[STRUC{[STYL{In conclusion, to sum up|In conclusion}][PUNC{,|;}] the evidence suggests three outcomes.|In conclusion; the evidence suggests three outcomes.}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STRUC");
        assert_eq!(result.corrections[0].children.len(), 2);
        assert_eq!(result.corrections[0].children[0].error_type, "STYL");
        assert_eq!(result.corrections[0].children[1].error_type, "PUNC");

        // Test segments
        assert_eq!(result.segments.len(), 1);
        match &result.segments[0] {
            TextSegment::Correction {
                error_type,
                children,
                original,
                ..
            } => {
                assert_eq!(error_type, "STRUC");
                assert_eq!(children.len(), 2);
                assert_eq!(
                    original,
                    "In conclusion, to sum up, the evidence suggests three outcomes."
                );
            }
            _ => panic!("Expected Correction segment"),
        }

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(
            original,
            "In conclusion, to sum up, the evidence suggests three outcomes."
        );
        assert_eq!(
            corrected,
            "In conclusion; the evidence suggests three outcomes."
        );
    }

    #[test]
    fn test_deeply_nested_corrections() {
        let input = "[STRUC{[STYL{This [GRAM{have|has}] [TYPO{multipel|multiple}] [PUNC{,|;}] nested corrections.|This has multiple; nested corrections.}]|A better sentence structure.}]";
        let result = parse_corrections_debug(input).unwrap();

        // Test segments
        assert_eq!(result.segments.len(), 1);

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This have multipel, nested corrections.");
        assert_eq!(corrected, "A better sentence structure.");

        // Print the segment structure for debugging
        print_segment_structure(&result.segments, 0);
    }

    #[test]
    fn test_mixed_text_and_corrections() {
        let input = "This is normal text. [TYPO{Thiz|This}] is a correction. And [GRAM{here are|here is}] another one.";
        let result = parse_corrections(input).unwrap();

        // Test segments
        assert_eq!(result.segments.len(), 5);

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(
            original,
            "This is normal text. Thiz is a correction. And here are another one."
        );
        assert_eq!(
            corrected,
            "This is normal text. This is a correction. And here is another one."
        );
    }

    #[test]
    fn test_segment_reconstruction() {
        let input = "This [TYPO{sentance|sentence}] has [GRAM{many error|many errors}].";
        let result = parse_corrections(input).unwrap();

        // Manually check each segment
        assert_eq!(result.segments.len(), 4);

        match &result.segments[0] {
            TextSegment::Plain(text) => assert_eq!(text, "This "),
            _ => panic!("Expected Plain segment"),
        }

        match &result.segments[1] {
            TextSegment::Correction {
                original,
                correction,
                ..
            } => {
                assert_eq!(original, "sentance");
                assert_eq!(correction, "sentence");
            }
            _ => panic!("Expected Correction segment"),
        }

        match &result.segments[2] {
            TextSegment::Plain(text) => assert_eq!(text, " has "),
            _ => panic!("Expected Plain segment"),
        }

        match &result.segments[3] {
            TextSegment::Correction {
                original,
                correction,
                ..
            } => {
                assert_eq!(original, "many error");
                assert_eq!(correction, "many errors");
            }
            _ => panic!("Expected Correction segment"),
        }

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This sentance has many error.");
        assert_eq!(corrected, "This sentence has many errors.");
    }

    #[test]
    fn test_nested_segment_reconstruction() {
        let input = "[STYL{This sentence has [GRAM{a error|an error}] in it.|This sentence has an error in it.}]";
        let result = parse_corrections(input).unwrap();

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This sentence has a error in it.");
        assert_eq!(corrected, "This sentence has an error in it.");
    }

    // Helper function to print the structure of segments
    fn print_segment_structure(segments: &[TextSegment], indent: usize) {
        for (i, segment) in segments.iter().enumerate() {
            let indent_str = " ".repeat(indent * 2);
            match segment {
                TextSegment::Plain(text) => {
                    println!("{}Segment #{}: Plain: {}", indent_str, i + 1, text);
                }
                TextSegment::Correction {
                    error_type,
                    original,
                    correction,
                    explanation,
                    children,
                    original_segments,
                    corrected_segments,
                } => {
                    println!(
                        "{}Segment #{}: Correction: {}",
                        indent_str,
                        i + 1,
                        error_type
                    );
                    println!("{}  Original: {}", indent_str, original);
                    println!("{}  Correction: {}", indent_str, correction);

                    if let Some(exp) = explanation {
                        println!("{}  Explanation: {}", indent_str, exp);
                    }

                    if !children.is_empty() {
                        println!("{}  Children:", indent_str);
                        print_segment_structure(children, indent + 1);
                    }

                    println!("{}  Original Segments:", indent_str);
                    print_segment_structure(original_segments, indent + 1);

                    println!("{}  Corrected Segments:", indent_str);
                    print_segment_structure(corrected_segments, indent + 1);
                }
            }
        }
    }

    // Helper function to print the structure of corrections
    fn print_correction_structure(corrections: &[Correction], indent: usize) {
        for (i, correction) in corrections.iter().enumerate() {
            let indent_str = " ".repeat(indent * 2);
            println!(
                "{}Correction #{}: {}",
                indent_str,
                i + 1,
                correction.error_type
            );
            println!("{}  Original: {}", indent_str, correction.original);
            println!("{}  Correction: {}", indent_str, correction.correction);

            if let Some(explanation) = &correction.explanation {
                println!("{}  Explanation: {}", indent_str, explanation);
            }

            if !correction.children.is_empty() {
                println!("{}  Children:", indent_str);
                print_correction_structure(&correction.children, indent + 1);
            }
        }
    }

    #[test]
    fn test_complex_nested_segment_reconstruction() {
        let input = "[STRUC{[STYL{In conclusion, to sum up|In conclusion}][PUNC{,|;}] the evidence suggests three outcomes.|In conclusion; the evidence suggests three outcomes.}]";
        let result = parse_corrections_debug(input).unwrap();

        // Print the segment structure for debugging
        println!("Complex nested segment structure:");
        print_segment_structure(&result.segments, 0);

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(
            original,
            "In conclusion, to sum up, the evidence suggests three outcomes."
        );
        assert_eq!(
            corrected,
            "In conclusion; the evidence suggests three outcomes."
        );
    }

    #[test]
    fn test_deeply_nested_segment_reconstruction() {
        let input = "[STRUC{[STYL{This [GRAM{have|has}] [TYPO{multipel|multiple}] [PUNC{,|;}] nested corrections.|This has multiple; nested corrections.}]|A better sentence structure.}]";
        let result = parse_corrections_debug(input).unwrap();

        // Print the segment structure for debugging
        println!("Deeply nested segment structure:");
        print_segment_structure(&result.segments, 0);

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This have multipel, nested corrections.");
        assert_eq!(corrected, "A better sentence structure.");
    }

    #[test]
    fn test_long_complex_text() {
        let input = r#"[GRAM{If I could travel anywere|If I could travel anywhere}][TYPO{wood|would}] go to Japan[PUNC{,|}][STYL{becuase|because}][TYPO{there|their}][GRAM{there culture|their culture}][TYPO{intresting|interesting}]. [WORD{I herd|I have heard}][STYL{the food is amazing, and they're|that the food is amazing, and their}][GRAM{they're|their}][TYPO{beutiful|beautiful}]. [STYL{I think it would be a very good|I think it would be a wonderful}][WORD{very good|wonderful}] experience to learn about [GRAM{they're|their}] history."#;

        let result = parse_corrections(input).unwrap();

        // Test reconstruction
        let parser = Parser::new();
        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        // Check that we can reconstruct both versions
        assert!(original.contains("If I could travel anywere"));
        assert!(original.contains("wood go to Japan"));
        assert!(original.contains("becuase"));
        assert!(original.contains("there culture"));
        assert!(original.contains("intresting"));

        assert!(corrected.contains("If I could travel anywhere"));
        assert!(corrected.contains("would go to Japan"));
        assert!(corrected.contains("because"));
        assert!(corrected.contains("their culture"));
        assert!(corrected.contains("interesting"));
    }

    #[test]
    fn test_segment_indexing() {
        let input = "This is [TYPO{normel|normal}] text with [GRAM{a correction|corrections}].";
        let result = parse_corrections(input).unwrap();

        // Test that we can access segments by index
        assert_eq!(result.segments.len(), 5);

        // First segment should be plain text
        match &result.segments[0] {
            TextSegment::Plain(text) => assert_eq!(text, "This is "),
            _ => panic!("Expected Plain segment"),
        }

        // Second segment should be a correction
        match &result.segments[1] {
            TextSegment::Correction {
                error_type,
                original,
                correction,
                ..
            } => {
                assert_eq!(error_type, "TYPO");
                assert_eq!(original, "normel");
                assert_eq!(correction, "normal");
            }
            _ => panic!("Expected Correction segment"),
        }

        // Third segment should be plain text
        match &result.segments[2] {
            TextSegment::Plain(text) => assert_eq!(text, " text with "),
            _ => panic!("Expected Plain segment"),
        }

        // Fourth segment should be a correction
        match &result.segments[3] {
            TextSegment::Correction {
                error_type,
                original,
                correction,
                ..
            } => {
                assert_eq!(error_type, "GRAM");
                assert_eq!(original, "a correction");
                assert_eq!(correction, "corrections");
            }
            _ => panic!("Expected Correction segment"),
        }

        // Fifth segment should be plain text
        match &result.segments[4] {
            TextSegment::Plain(text) => assert_eq!(text, "."),
            _ => panic!("Expected Plain segment"),
        }
    }

    #[test]
    fn test_empty_input() {
        let input = "";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.text, "");
        assert_eq!(result.corrections.len(), 0);
        assert_eq!(result.suggestions, None);
        assert_eq!(result.segments.len(), 0);
    }

    #[test]
    fn test_correction_with_explanation() {
        let input = "This has a [TYPO{mispeling|misspelling|Common spelling error}] in it.";
        let result = parse_corrections(input).unwrap();

        // Check the explanation is properly parsed
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(
            result.corrections[0].explanation,
            Some("Common spelling error".to_string())
        );

        // Check the segment also has the explanation
        match &result.segments[1] {
            TextSegment::Correction { explanation, .. } => {
                assert_eq!(explanation, &Some("Common spelling error".to_string()));
            }
            _ => panic!("Expected Correction segment"),
        }
    }
}


