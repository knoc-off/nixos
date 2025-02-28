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
        let (parsed_text, corrections) = self.parse_nested_corrections(main_text)?;

        Ok(ParsedText {
            text: parsed_text,
            corrections,
            suggestions,
        })
    }

    // Modify the parse_nested_corrections method to handle adjacent corrections
    fn parse_nested_corrections(
        &self,
        text: &str,
    ) -> Result<(String, Vec<Correction>), ParserError> {
        let mut result = String::new();
        let mut corrections = Vec::new();
        let mut current_pos = 0;
        let text_chars: Vec<char> = text.chars().collect();

        while current_pos < text_chars.len() {
            if current_pos + 1 < text_chars.len() && text_chars[current_pos] == '[' {
                // This might be the start of a correction
                match self.try_parse_correction(&text_chars, current_pos, 0) {
                    Ok((Some(parsed), new_pos)) => {
                        if self.debug_mode {
                            println!("Successfully parsed correction: {:?}", parsed);
                        }

                        // Add the correction to our list
                        corrections.push(parsed);

                        // Add the corrected text to the result
                        result.push_str(&corrections.last().unwrap().correction);
                        current_pos = new_pos;
                    }
                    Ok((None, new_pos)) => {
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

        Ok((result, corrections))
    }

    // Modify the try_parse_correction method to better handle brackets and braces
    fn try_parse_correction(
        &self,
        chars: &[char],
        start_pos: usize,
        depth: usize,
    ) -> Result<(Option<Correction>, usize), ParserError> {
        // Check recursion depth
        if depth > 100 {
            // Set a reasonable maximum
            return Err(ParserError::RecursiveError(start_pos.to_string()));
        }
        // Check if this is the start of a correction
        if chars[start_pos] != '[' {
            return Ok((None, start_pos + 1));
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
            return Ok((None, start_pos + 1));
        }

        // Parse the content inside the curly braces
        if pos >= chars.len() {
            return Err(ParserError::UnexpectedEndOfInput(pos));
        }

        if chars[pos] != '{' {
            if self.debug_mode {
                println!("Expected '{{' at position {}, found '{}'", pos, chars[pos]);
            }
            return Ok((None, start_pos + 1));
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

        // Parse the original text (which may contain nested corrections)
        let mut brace_count = 1;
        let mut in_original = true;
        let mut in_correction = false;
        let mut in_explanation = false;

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
                        match self.try_parse_correction(chars, pos, depth + 1) {
                            Ok((Some(nested), new_pos)) => {
                                children.push(nested.clone());
                                // Add the nested correction's original text
                                original.push_str(&nested.original);
                                pos = new_pos;
                                continue;
                            }
                            Ok((None, _)) => {
                                // Not a nested correction, treat as regular character
                                original.push(chars[pos]);
                            }
                            Err(e) => {
                                if self.debug_mode {
                                    println!("Error parsing nested correction: {}", e);
                                }
                                // On error, just treat as regular text
                                original.push(chars[pos]);
                            }
                        }
                    } else {
                        // Just a regular bracket in the content
                        original.push(chars[pos]);
                    }
                } else if chars[pos] == '|' && brace_count == 1 {
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
            return Ok((None, start_pos + 1));
        }

        let explanation = if explanation.is_empty() {
            None
        } else {
            Some(explanation)
        };

        let correction = Correction {
            error_type: error_type.to_string(),
            original,
            correction,
            explanation,
            children,
        };

        Ok((Some(correction), pos))
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
    }
    #[test]
    fn test_empty_input() {
        let input = "";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.text, "");
        assert_eq!(result.corrections.len(), 0);
        assert_eq!(result.suggestions, None);
    }

    #[test]
    fn test_no_corrections() {
        let input = "This is a text with no corrections.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.text, "This is a text with no corrections.");
        assert_eq!(result.corrections.len(), 0);
    }

    #[test]
    fn test_correction_with_explanation() {
        let input = "This has a [TYPO{mispeling|misspelling|Common spelling error}] in it.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "misspelling");
        assert_eq!(
            result.corrections[0].explanation,
            Some("Common spelling error".to_string())
        );
    }

    #[test]
    fn test_adjacent_corrections() {
        let input = "This [TYPO{sentance|sentence}][PUNC{|,}] needs fixing.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 2);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "sentance");
        assert_eq!(result.corrections[0].correction, "sentence");
        assert_eq!(result.corrections[1].error_type, "PUNC");
        assert_eq!(result.corrections[1].original, "");
        assert_eq!(result.corrections[1].correction, ",");
        assert_eq!(result.text, "This sentence, needs fixing.");
    }

    #[test]
    fn test_correction_with_braces_in_content() {
        let input = "The function [GRAM{look like: function() { return x; }|looks like: function() { return x; }}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "GRAM");
        assert_eq!(
            result.corrections[0].original,
            "look like: function() { return x; }"
        );
        assert_eq!(
            result.corrections[0].correction,
            "looks like: function() { return x; }"
        );
    }

    #[test]
    fn test_correction_with_brackets_in_content() {
        let input = "The array [TYPO{[1,2,3]|[1, 2, 3]}] needs spaces.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "[1,2,3]");
        assert_eq!(result.corrections[0].correction, "[1, 2, 3]");
    }

    #[test]
    fn test_deeply_nested_corrections() {
        let input = "[STRUC{[STYL{This [GRAM{have|has}] [TYPO{multipel|multiple}] [PUNC{,|;}] nested corrections.|This has multiple; nested corrections.}]|A better sentence structure.}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STRUC");
        assert_eq!(result.corrections[0].children.len(), 1);
        assert_eq!(result.corrections[0].children[0].error_type, "STYL");
        assert_eq!(result.corrections[0].children[0].children.len(), 3);
        assert_eq!(
            result.corrections[0].children[0].children[0].error_type,
            "GRAM"
        );
        assert_eq!(
            result.corrections[0].children[0].children[1].error_type,
            "TYPO"
        );
        assert_eq!(
            result.corrections[0].children[0].children[2].error_type,
            "PUNC"
        );
    }

    #[test]
    fn test_suggestions_with_corrections() {
        let input = "This [TYPO{sentance|sentence}] needs fixing.\n\n[SUGGESTIONS]\n1. Use more precise language.\n2. Consider adding examples.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert!(result.suggestions.is_some());
        assert!(result
            .suggestions
            .unwrap()
            .contains("Use more precise language"));
    }

    #[test]
    fn test_malformed_correction_recovery() {
        // Missing closing bracket but parser should recover
        let input = "This has a [TYPO{mispeling|misspelling in it.";
        let result = parse_corrections(input).unwrap();
        // The parser should treat the malformed correction as regular text
        assert_eq!(result.text, "This has a [TYPO{mispeling|misspelling in it.");
        assert_eq!(result.corrections.len(), 0);
    }

    #[test]
    fn test_invalid_error_type() {
        // Invalid error type should be treated as regular text
        let input = "This has a [INVALID{mispeling|misspelling}] in it.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(
            result.text,
            "This has a [INVALID{mispeling|misspelling}] in it."
        );
        assert_eq!(result.corrections.len(), 0);
    }

    #[test]
    fn test_correction_at_start() {
        let input = "[TYPO{Mispeling|Misspelling}] at the start.";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].original, "Mispeling");
        assert_eq!(result.corrections[0].correction, "Misspelling");
    }

    #[test]
    fn test_correction_at_end() {
        let input = "Error at the end: [GRAM{is wrong|are wrong}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].original, "is wrong");
        assert_eq!(result.corrections[0].correction, "are wrong");
    }

    #[test]
    fn test_multiline_correction() {
        let input = "This has a [STRUC{paragraph that\nis poorly\nstructured.|paragraph that is well structured.}]";
        let result = parse_corrections(input).unwrap();
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STRUC");
        assert!(result.corrections[0].original.contains("\n"));
    }

    #[test]
    fn test_long_complex_text_2() {
        // The input text has double braces {{...}} instead of single braces {....}
        // Let's modify the input to use single braces
        let input = r#"[GRAM{If I could travel anywere|If I could travel anywhere}][TYPO{wood|would}] go to Japan[PUNC{,|}][STYL{becuase|because}][TYPO{there|their}][GRAM{there culture|their culture}][TYPO{intresting|interesting}]. [WORD{I herd|I have heard}][STYL{the food is amazing, and they're|that the food is amazing, and their}][GRAM{they're|their}][TYPO{beutiful|beautiful}]. [STYL{I think it would be a very good|I think it would be a wonderful}][WORD{very good|wonderful}] experience to learn about [GRAM{they're|their}] history.

[STRUC{Also, Tokyo, its a very big city, I think it will be fun.|Additionally, Tokyo is a very large city, and I believe it would be exciting to explore.}][STYL{Also|Additionally}][GRAM{its|is}][WORD{big|large}][PUNC{city,|city,}][STYL{I think it will be fun|and I believe it would be exciting to explore}]. [WORD{intrested|fascinated}][TYPO{intrested|fascinated}] by Mount Fuji[PUNC{,|, as}][GRAM{it looks majestic.|it looks majestic.}]

[GRAM{I hope I can go their someday,|I hope I can visit someday—}][TYPO{their|there}][PUNC{,|—}][STYL{it would be|it would truly be}] a dream come true.

[STRUC{I think it would be a good experience for me to learn about they're culture.|Overall, I think traveling to Japan would be an incredible opportunity for me to learn about its culture and history while experiencing everything the country has to offer.}][GRAM{they're|its}][STYL{good experience|incredible opportunity}]

[STRUC{In conclusion, I think Japan is good.|In conclusion, Japan is a fascinating destination, and I would love to visit.}][STYL{good|fascinating destination}]"#;

        // Use debug mode to get more information
        let result = parse_corrections_debug(input);

        // Check if parsing was successful
        assert!(
            result.is_ok(),
            "Failed to parse the text: {:?}",
            result.err()
        );

        let parsed = result.unwrap();

        // Print the structure for analysis
        println!("Parsed Text: {}", parsed.text);
        println!(
            "Number of top-level corrections: {}",
            parsed.corrections.len()
        );

        // Print detailed structure of corrections
        print_correction_structure(&parsed.corrections, 0);

        // Verify some specific corrections
        assert!(parsed.corrections.iter().any(|c| c.error_type == "GRAM"
            && c.original == "If I could travel anywere"
            && c.correction == "If I could travel anywhere"));

        assert!(parsed
            .corrections
            .iter()
            .any(|c| c.error_type == "TYPO" && c.original == "wood" && c.correction == "would"));

        // Check for the STRUC correction in the last paragraph
        let last_struc = parsed.corrections.iter().find(|c|
        c.error_type == "STRUC" &&
        c.original == "In conclusion, I think Japan is good." &&
        c.correction == "In conclusion, Japan is a fascinating destination, and I would love to visit."
    );

        assert!(
            last_struc.is_some(),
            "Could not find the expected STRUC correction in the last paragraph"
        );

        // Check for duplicate corrections (intrested|fascinated appears twice)
        let fascinated_corrections = parsed
            .corrections
            .iter()
            .filter(|c| c.original == "intrested" && c.correction == "fascinated")
            .count();

        assert_eq!(
            fascinated_corrections, 2,
            "Expected to find 'intrested|fascinated' correction twice"
        );

        // Check for empty correction in PUNC
        let empty_correction = parsed
            .corrections
            .iter()
            .find(|c| c.error_type == "PUNC" && c.original == "," && c.correction == "");

        assert!(
            empty_correction.is_some(),
            "Could not find the empty PUNC correction"
        );

        // Check for redundant correction
        let redundant_correction = parsed.corrections.iter().find(|c| {
            c.error_type == "GRAM"
                && c.original == "it looks majestic."
                && c.correction == "it looks majestic."
        });

        assert!(
            redundant_correction.is_some(),
            "Could not find the redundant GRAM correction"
        );
    }

    #[test]
    fn test_long_complex_text() {
        let input = r#"[GRAM{{If I could travel anywere|If I could travel anywhere}}][TYPO{{wood|would}}] go to Japan[PUNC{{,|}}][STYL{{becuase|because}}][TYPO{{there|their}}][GRAM{{there culture|their culture}}][TYPO{{intresting|interesting}}]. [WORD{{I herd|I have heard}}][STYL{{the food is amazing, and they're|that the food is amazing, and their}}][GRAM{{they're|their}}][TYPO{{beutiful|beautiful}}]. [STYL{{I think it would be a very good|I think it would be a wonderful}}][WORD{{very good|wonderful}}] experience to learn about [GRAM{{they're|their}}] history.

[STRUC{{Also, Tokyo, its a very big city, I think it will be fun.|Additionally, Tokyo is a very large city, and I believe it would be exciting to explore.}}][STYL{{Also|Additionally}}][GRAM{{its|is}}][WORD{{big|large}}][PUNC{{city,|city,}}][STYL{{I think it will be fun|and I believe it would be exciting to explore}}]. [WORD{{intrested|fascinated}}][TYPO{{intrested|fascinated}}] by Mount Fuji[PUNC{{,|, as}}][GRAM{{it looks majestic.|it looks majestic.}}]

[GRAM{{I hope I can go their someday,|I hope I can visit someday—}}][TYPO{{their|there}}][PUNC{{,|—}}][STYL{{it would be|it would truly be}}] a dream come true.

[STRUC{{[Repeated 3x] I think it would be a good experience for me to learn about they're culture.|Overall, I think traveling to Japan would be an incredible opportunity for me to learn about its culture and history while experiencing everything the country has to offer.}}][GRAM{{they're|its}}][STYL{{good experience|incredible opportunity}}]

[STRUC{{In conclusion, I think Japan is good.|In conclusion, Japan is a fascinating destination, and I would love to visit.}}][STYL{{good|fascinating destination}}]"#;

        // Use debug mode to get more information
        let result = parse_corrections_debug(input);

        // Check if parsing was successful
        assert!(
            result.is_ok(),
            "Failed to parse the text: {:?}",
            result.err()
        );

        let parsed = result.unwrap();

        // Print the structure for analysis
        println!("Parsed Text: {}", parsed.text);
        println!(
            "Number of top-level corrections: {}",
            parsed.corrections.len()
        );

        // Print detailed structure of corrections
        print_correction_structure(&parsed.corrections, 0);

        // Verify some specific corrections
        assert!(parsed.corrections.iter().any(|c| c.error_type == "GRAM"
            && c.original == "If I could travel anywere"
            && c.correction == "If I could travel anywhere"));

        assert!(parsed
            .corrections
            .iter()
            .any(|c| c.error_type == "TYPO" && c.original == "wood" && c.correction == "would"));

        // Check for the STRUC correction in the last paragraph
        let last_struc = parsed.corrections.iter().find(|c|
        c.error_type == "STRUC" &&
        c.original == "In conclusion, I think Japan is good." &&
        c.correction == "In conclusion, Japan is a fascinating destination, and I would love to visit."
    );

        assert!(
            last_struc.is_some(),
            "Could not find the expected STRUC correction in the last paragraph"
        );
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
}
