use html_escape::decode_html_entities;
use regex::Regex;
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
        original_segments: Vec<TextSegment>,
        corrected_segments: Vec<TextSegment>,
    },
}

#[derive(Debug, Error)]
pub enum ParserError {
    #[error("Invalid XML: {0}")]
    InvalidXml(String),

    #[error("Missing required attribute: {0}")]
    MissingAttribute(String),

    #[error("Invalid error type: {0}")]
    InvalidErrorType(String),

    #[error("JSON serialization error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Regex error: {0}")]
    RegexError(#[from] regex::Error),
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ParsedText {
    pub text: String,
    pub corrections: Vec<Correction>,
    pub suggestions: Option<String>,
    pub segments: Vec<TextSegment>,
}

pub struct XmlParser {
    debug_mode: bool,
}

impl XmlParser {
    pub fn new() -> Self {
        Self { debug_mode: false }
    }

    pub fn with_debug(mut self, debug: bool) -> Self {
        self.debug_mode = debug;
        self
    }

    pub fn parse(&self, xml: &str) -> Result<ParsedText, ParserError> {
        // Extract content from document/content tags
        let content_regex = Regex::new(r"<content>(.*?)</content>")?;
        let content = if let Some(captures) = content_regex.captures(xml) {
            captures.get(1).map(|m| m.as_str().trim().to_string())
        } else {
            None
        };

        let content = match content {
            Some(c) => c,
            None => return Err(ParserError::InvalidXml("Missing content tag".to_string())),
        };

        // Extract suggestions if present
        let suggestions_regex = Regex::new(r"<suggestions>(.*?)</suggestions>")?;
        let suggestions = if let Some(captures) = suggestions_regex.captures(xml) {
            Some(decode_html_entities(&captures[1]).to_string())
        } else {
            None
        };

        // Process the main content
        let (segments, corrections) = self.parse_content(&content)?;

        // Reconstruct the plain text from segments
        let text = self.reconstruct_original(&segments);

        Ok(ParsedText {
            text,
            corrections,
            suggestions,
            segments,
        })
    }

    fn parse_content(
        &self,
        content: &str,
    ) -> Result<(Vec<TextSegment>, Vec<Correction>), ParserError> {
        let mut segments = Vec::new();
        let mut corrections = Vec::new();
        let mut current_pos = 0;

        // Create regex for finding correction tags
        let correction_regex = Regex::new(
            r#"<correction\s+type="([^"]+)"(?:\s+explanation="([^"]+)")?\s*>(.*?)</correction>"#,
        )?;

        while let Some(capture) = correction_regex
            .captures_iter(content)
            .find(|c| c.get(0).unwrap().start() >= current_pos)
        {
            let whole_match = capture.get(0).unwrap();
            let error_type = capture.get(1).unwrap().as_str();
            let explanation = capture
                .get(2)
                .map(|m| decode_html_entities(m.as_str()).to_string());
            let inner_content = capture.get(3).unwrap().as_str();

            // Add any text before this correction as plain text
            if whole_match.start() > current_pos {
                let plain_text = &content[current_pos..whole_match.start()];
                if !plain_text.is_empty() {
                    segments.push(TextSegment::Plain(
                        decode_html_entities(plain_text).to_string(),
                    ));
                }
            }

            // Extract original and corrected text
            let (original, correction, original_segments) =
                self.extract_original_and_correction(inner_content)?;

            // Recursively parse any nested corrections
            let (child_segments, child_corrections) = self.parse_content(inner_content)?;

            // Create the correction object
            let correction_obj = Correction {
                error_type: error_type.to_string(),
                original: original.clone(),
                correction: correction.clone(),
                explanation: explanation.clone(),
                children: child_corrections,
            };

            corrections.push(correction_obj);

            // Create corrected segments
            let corrected_segments = vec![TextSegment::Plain(correction.clone())];

            // Add the correction segment
            segments.push(TextSegment::Correction {
                error_type: error_type.to_string(),
                original: original.clone(),
                correction: correction.clone(),
                explanation,
                children: child_segments,
                original_segments: if original_segments.is_empty() {
                    vec![TextSegment::Plain(original.clone())]
                } else {
                    original_segments
                },
                corrected_segments,
            });

            current_pos = whole_match.end();
        }

        // Add any remaining text as plain text
        if current_pos < content.len() {
            let plain_text = &content[current_pos..];
            if !plain_text.is_empty() {
                segments.push(TextSegment::Plain(
                    decode_html_entities(plain_text).to_string(),
                ));
            }
        }

        Ok((segments, corrections))
    }

    fn extract_original_and_correction(
        &self,
        content: &str,
    ) -> Result<(String, String, Vec<TextSegment>), ParserError> {
        // Look for original and corrected tags
        let original_regex = Regex::new(r"<original>(.*?)</original>")?;
        let corrected_regex = Regex::new(r"<corrected>(.*?)</corrected>")?;

        let (original, original_segments) = if let Some(captures) = original_regex.captures(content)
        {
            let original_content = captures[1].trim();
            // Parse the original content to get any nested segments
            let (segments, _) = self.parse_content(original_content)?;

            // Reconstruct the plain text from the original content
            let plain_text = self.reconstruct_original(&segments);
            (plain_text, segments)
        } else {
            // If no original tag, use the content with any nested correction tags removed
            let no_tags_regex = Regex::new(r"</?(?:correction|original|corrected)[^>]*>")?;
            let plain_text = no_tags_regex.replace_all(content, "").to_string();
            (plain_text.trim().to_string(), Vec::new())
        };

        let correction = if let Some(captures) = corrected_regex.captures(content) {
            decode_html_entities(&captures[1]).trim().to_string()
        } else {
            // If no corrected tag, use the original text
            original.clone()
        };

        Ok((original, correction, original_segments))
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
pub fn parse_xml_corrections(xml: &str) -> Result<ParsedText, ParserError> {
    let parser = XmlParser::new();
    parser.parse(xml)
}

// Convenience function with debug mode
pub fn parse_xml_corrections_debug(xml: &str) -> Result<ParsedText, ParserError> {
    let parser = XmlParser::new().with_debug(true);
    parser.parse(xml)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_correction() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO" explanation="Common spelling error">
              <original>mispeling</original>
              <corrected>misspelling</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.text, "This has a mispeling in it.");
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "TYPO");
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "misspelling");
        assert_eq!(
            result.corrections[0].explanation,
            Some("Common spelling error".to_string())
        );

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
                explanation,
                ..
            } => {
                assert_eq!(error_type, "TYPO");
                assert_eq!(original, "mispeling");
                assert_eq!(correction, "misspelling");
                assert_eq!(explanation, &Some("Common spelling error".to_string()));
            }
            _ => panic!("Expected Correction segment"),
        }
        match &result.segments[2] {
            TextSegment::Plain(text) => assert_eq!(text, " in it."),
            _ => panic!("Expected Plain segment"),
        }
    }

    #[test]
    fn test_multiple_corrections() {
        let xml = r#"
        <document>
          <content>
            The team <correction type="GRAM">
              <original>is</original>
              <corrected>are</corrected>
            </correction> <correction type="WORD">
              <original>leveraging</original>
              <corrected>using</corrected>
            </correction> their resources effectively.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(
            result.text,
            "The team is leveraging their resources effectively."
        );
        assert_eq!(result.corrections.len(), 2);

        // Check first correction
        assert_eq!(result.corrections[0].error_type, "GRAM");
        assert_eq!(result.corrections[0].original, "is");
        assert_eq!(result.corrections[0].correction, "are");

        // Check second correction
        assert_eq!(result.corrections[1].error_type, "WORD");
        assert_eq!(result.corrections[1].original, "leveraging");
        assert_eq!(result.corrections[1].correction, "using");

        // Test segments
        assert_eq!(result.segments.len(), 5);
    }

    #[test]
    fn test_nested_corrections() {
        let xml = r#"
        <document>
          <content>
            <correction type="STYL" explanation="Improved overall style">
              <original>
                This sentence has
                <correction type="GRAM">
                  <original>a error</original>
                  <corrected>an error</corrected>
                </correction>
                that needs fixing.
              </original>
              <corrected>This sentence has an error that needs fixing.</corrected>
            </correction>
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].error_type, "STYL");
        assert_eq!(result.corrections[0].children.len(), 1);
        assert_eq!(result.corrections[0].children[0].error_type, "GRAM");
        assert_eq!(result.corrections[0].children[0].original, "a error");
        assert_eq!(result.corrections[0].children[0].correction, "an error");
    }

    #[test]
    fn test_with_suggestions() {
        let xml = r#"
        <document>
          <content>
            This is a simple text.
          </content>
          <suggestions>
            1. Consider using more specific examples.
            2. Try to vary your sentence structure more.
          </suggestions>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.text, "This is a simple text.");
        assert!(result.corrections.is_empty());
        assert_eq!(
            result.suggestions,
            Some("1. Consider using more specific examples.\n            2. Try to vary your sentence structure more.".to_string())
        );
    }

    #[test]
    fn test_html_entity_decoding() {
        let xml = r#"
        <document>
          <content>
            This has &amp; special &lt;characters&gt; and a <correction type="TYPO">
              <original>mispeling &amp; stuff</original>
              <corrected>misspelling &amp; things</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(
            result.text,
            "This has & special <characters> and a mispeling & stuff in it."
        );
        assert_eq!(result.corrections[0].original, "mispeling & stuff");
        assert_eq!(result.corrections[0].correction, "misspelling & things");
    }

    #[test]
    fn test_reconstruct_corrected() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO">
              <original>mispeling</original>
              <corrected>misspelling</corrected>
            </correction> and <correction type="GRAM">
              <original>a error</original>
              <corrected>an error</corrected>
            </correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();
        let parser = XmlParser::new();

        let original = parser.reconstruct_original(&result.segments);
        let corrected = parser.reconstruct_corrected(&result.segments);

        assert_eq!(original, "This has a mispeling and a error in it.");
        assert_eq!(corrected, "This has a misspelling and an error in it.");
    }

    #[test]
    fn test_correction_without_explicit_tags() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO">mispeling</correction> in it.
          </content>
        </document>
        "#;

        let result = parse_xml_corrections(xml).unwrap();

        assert_eq!(result.text, "This has a mispeling in it.");
        assert_eq!(result.corrections.len(), 1);
        assert_eq!(result.corrections[0].original, "mispeling");
        assert_eq!(result.corrections[0].correction, "mispeling");
    }

    #[test]
    fn test_error_handling_invalid_xml() {
        let xml = r#"
        <document>
          <content>
            This has a <correction type="TYPO">mispeling</content>
        </document>
        "#;

        let result = parse_xml_corrections(xml);
        assert!(result.is_err());
    }

    #[test]
    fn test_complex_document() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
    <document>
      <content>
        <correction type="STYL" explanation="This paragraph has been restructured for clarity">
          <original>
            The research team conducted a study on climate change effects. They collected data from
            <correction type="TYPO" explanation="Spelling error">
              <original>fourty</original>
              <corrected>forty</corrected>
            </correction>
            different locations across the globe. The data
            <correction type="GRAM">
              <original>was</original>
              <corrected>were</corrected>
            </correction>
            analyzed using advanced statistical methods.
          </original>
          <corrected>
            The research team conducted a comprehensive global study on climate change effects. They collected and analyzed data from forty different locations using advanced statistical methods.
          </corrected>
        </correction>

        This paragraph contains several common errors. The author
        <correction type="VERB" explanation="Incorrect verb tense">
          <original>use</original>
          <corrected>uses</corrected>
        </correction>
        incorrect verb forms and
        <correction type="PUNCT" explanation="Missing comma in compound sentence">
          <original>sometimes forgets punctuation</original>
          <corrected>sometimes forgets punctuation,</corrected>
        </correction>
        which makes the text harder to read.
      </content>

      <suggestions>
        1. Consider using more specific examples to illustrate your points.
        2. The introduction would benefit from a clearer thesis statement.
      </suggestions>
    </document>"#;

        let result = parse_xml_corrections(xml).unwrap();

        // Check that we have the right number of top-level corrections
        assert_eq!(result.corrections.len(), 3);

        // Check that the first correction has nested corrections
        assert_eq!(result.corrections[0].children.len(), 2);

        // Check that suggestions were parsed correctly
        assert!(result.suggestions.unwrap().contains("specific examples"));

        // Check that the reconstructed text is correct
        let parser = XmlParser::new();
        let corrected = parser.reconstruct_corrected(&result.segments);
        assert!(corrected.contains("uses"));
        assert!(corrected.contains("punctuation,"));
    }
}
