use quick_xml::events::Event;
use quick_xml::Reader;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ParserError {
    #[error("XML parsing error: {0}")]
    XmlError(#[from] quick_xml::Error),

    #[error("Missing required element: {0}")]
    MissingElement(&'static str),

    #[error("Invalid correction structure: {0}")]
    InvalidStructure(&'static str),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Attribute error: {0}")]
    AttributeError(String),
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct ParsedText {
    pub original_text: String,
    pub corrected_text: String,
    pub corrections: Vec<Correction>,
    pub suggestions: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
pub struct Correction {
    pub error_type: String,
    pub original: String,
    pub correction: String,
    pub explanation: Option<String>,
    pub children: Vec<Correction>,
}

pub struct XmlParser {
    buffer_size: usize,
}

impl Default for XmlParser {
    fn default() -> Self {
        Self { buffer_size: 4096 }
    }
}

impl XmlParser {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_buffer_size(mut self, size: usize) -> Self {
        self.buffer_size = size;
        self
    }

    fn append_with_spacing(target: &mut String, text: &str) {
        if text.is_empty() {
            return;
        }

        // Check if text starts with punctuation
        let starts_with_punctuation = text.chars().next().map_or(false, |c| {
            matches!(c, ',' | '.' | ';' | ':' | '!' | '?' | ')' | ']' | '}')
        });

        // Don't add space if target is empty, ends with whitespace,
        // text starts with whitespace, or text starts with punctuation
        let need_space = !target.is_empty()
            && !target.ends_with('\n')
            && !target.ends_with(char::is_whitespace)
            && !text.chars().next().map_or(false, |c| c.is_whitespace())
            && !starts_with_punctuation;

        if need_space {
            target.push(' ');
        }
        target.push_str(text);
    }

    pub fn parse(&mut self, xml: &str) -> Result<ParsedText, ParserError> {
        let processed_xml = xml
            .replace("<br/>", "§NEWLINE§")
            .replace("<br />", "§NEWLINE§");

        let mut reader = Reader::from_str(&processed_xml);
        reader.config_mut().trim_text_start = true;
        reader.config_mut().trim_text_end = true;

        let mut parsed = ParsedText {
            original_text: String::new(),
            corrected_text: String::new(),
            corrections: Vec::new(),
            suggestions: None,
        };

        let mut buf = Vec::with_capacity(self.buffer_size);
        let mut correction_stack = Vec::new();
        let mut current_correction: Option<Correction> = None;
        let mut current_text = String::new();
        let mut in_element: Option<String> = None;

        // Track text content for each correction level
        let mut original_content_stack = Vec::new();
        let mut corrected_content_stack = Vec::new();

        loop {
            match reader.read_event_into(&mut buf) {
                Ok(Event::Start(e)) => {
                    let name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                    match name.as_str() {
                        "correction" => {
                            if current_correction.is_some() && !current_text.is_empty() {
                                if let Some(orig) = original_content_stack.last_mut() {
                                    Self::append_with_spacing(orig, current_text.trim());
                                }
                                if let Some(corr) = corrected_content_stack.last_mut() {
                                    Self::append_with_spacing(corr, current_text.trim());
                                }
                                current_text.clear();
                            }

                            //
                            // Process any text before this correction
                            if current_correction.is_none() && !current_text.is_empty() {
                                let text = current_text.trim();
                                Self::append_with_spacing(&mut parsed.original_text, text);
                                Self::append_with_spacing(&mut parsed.corrected_text, text);
                                current_text.clear();
                            }

                            let error_type = Self::get_attribute(&e, "type").map_err(|e| {
                                ParserError::AttributeError(format!(
                                    "Error getting 'type' attribute: {}",
                                    e
                                ))
                            })?;

                            let correction = Correction {
                                error_type,
                                explanation: None,
                                original: String::new(),
                                correction: String::new(),
                                children: Vec::new(),
                            };

                            // Push current correction to stack if it exists
                            if let Some(parent) = current_correction.take() {
                                correction_stack.push(parent);
                            }

                            // Initialize content tracking for this correction level
                            original_content_stack.push(String::new());
                            corrected_content_stack.push(String::new());

                            current_correction = Some(correction);
                        }
                        "original" | "corrected" | "explanation" | "suggestions" => {
                            in_element = Some(name);
                            current_text.clear();
                        }
                        "content" => {
                            // Just mark that we're in content element
                            in_element = Some(name);
                        }
                        _ => {}
                    }
                }

                Ok(Event::End(e)) => {
                    let name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                    match name.as_str() {
                        "correction" => {
                            let mut correction =
                                current_correction
                                    .take()
                                    .ok_or(ParserError::InvalidStructure(
                                        "Unmatched correction end tag",
                                    ))?;

                            // Get accumulated content for this correction level
                            let orig_content = original_content_stack.pop().unwrap_or_default();
                            let corr_content = corrected_content_stack.pop().unwrap_or_default();

                            // Use explicit original/corrected if available, otherwise use accumulated content
                            if correction.original.is_empty() {
                                correction.original = Self::normalize_whitespace(&orig_content);
                            }
                            if correction.correction.is_empty() {
                                correction.correction = Self::normalize_whitespace(&corr_content);
                            }

                            // Fallback: If one is still empty, use the other
                            if correction.original.is_empty() && !correction.correction.is_empty() {
                                correction.original = correction.correction.clone();
                            } else if correction.correction.is_empty()
                                && !correction.original.is_empty()
                            {
                                correction.correction = correction.original.clone();
                            }

                            // Handle top-level or parent corrections
                            if let Some(mut parent) = correction_stack.pop() {
                                // Add this correction as a child to the parent
                                parent.children.push(correction);
                                current_correction = Some(parent);
                            } else {
                                // This is a top-level correction
                                // IMPORTANT FIX: Only add to parsed text for top-level corrections
                                Self::append_with_spacing(
                                    &mut parsed.original_text,
                                    &correction.original,
                                );
                                Self::append_with_spacing(
                                    &mut parsed.corrected_text,
                                    &correction.correction,
                                );
                                parsed.corrections.push(correction);
                            }

                            current_text.clear();
                        }

                        "original" => {
                            if let Some(correction) = &mut current_correction {
                                correction.original = current_text.trim().to_string();
                            }
                            in_element = None;
                            current_text.clear();
                        }

                        "corrected" => {
                            if let Some(correction) = &mut current_correction {
                                correction.correction = current_text.trim().to_string();
                            }
                            in_element = None;
                            current_text.clear();
                        }

                        "explanation" => {
                            if let Some(correction) = &mut current_correction {
                                correction.explanation = Some(current_text.trim().to_string());
                            }
                            in_element = None;
                            current_text.clear();
                        }

                        "suggestions" => {
                            parsed.suggestions = Some(current_text.trim().to_string());
                            in_element = None;
                            current_text.clear();
                        }

                        "content" => {
                            // If we have text outside of any correction, add it to both original and corrected
                            if current_correction.is_none() && !current_text.is_empty() {
                                let text = current_text.trim();
                                Self::append_with_spacing(&mut parsed.original_text, text);
                                Self::append_with_spacing(&mut parsed.corrected_text, text);
                                current_text.clear();
                            }
                            in_element = None;
                        }

                        _ => {}
                    }
                }

                Ok(Event::Text(e)) => {
                    let text = e.unescape().map_err(ParserError::XmlError)?.into_owned();

                    // Skip pure whitespace text nodes
                    if text.trim().is_empty() {
                        continue;
                    }

                    match &in_element {
                        Some(element) if element == "original" => {
                            current_text.push_str(&text);
                        }
                        Some(element) if element == "corrected" => {
                            current_text.push_str(&text);
                        }
                        Some(element) if element == "explanation" => {
                            current_text.push_str(&text);
                        }
                        Some(element) if element == "suggestions" => {
                            current_text.push_str(&text);
                        }
                        Some(element) if element == "content" => {
                            if current_correction.is_some() {
                                // Inside a correction but in content element, add to both original and corrected
                                if let Some(orig) = original_content_stack.last_mut() {
                                    Self::append_with_spacing(orig, &text);
                                }
                                if let Some(corr) = corrected_content_stack.last_mut() {
                                    Self::append_with_spacing(corr, &text);
                                }
                            } else {
                                // Outside any correction, add to current_text
                                Self::append_with_spacing(&mut current_text, &text);
                            }
                        }
                        _ => {
                            if current_correction.is_some() {
                                // Direct text inside a correction
                                if let Some(orig) = original_content_stack.last_mut() {
                                    Self::append_with_spacing(orig, &text);
                                }
                                if let Some(corr) = corrected_content_stack.last_mut() {
                                    Self::append_with_spacing(corr, &text);
                                }
                            } else {
                                // Outside any correction
                                Self::append_with_spacing(&mut current_text, &text);
                            }
                        }
                    }
                }

                Ok(Event::Eof) => {
                    // Add any remaining text
                    if !current_text.is_empty() && current_correction.is_none() {
                        let text = current_text.trim();
                        Self::append_with_spacing(&mut parsed.original_text, text);
                        Self::append_with_spacing(&mut parsed.corrected_text, text);
                    }
                    break;
                }
                Err(e) => return Err(ParserError::XmlError(e)),
                _ => {}
            }

            buf.clear();
        }

        if parsed.original_text.is_empty() && !parsed.corrections.is_empty() {
            for correction in &parsed.corrections {
                Self::append_with_spacing(&mut parsed.original_text, &correction.original);
                Self::append_with_spacing(&mut parsed.corrected_text, &correction.correction);
            }
        }

        // Post-process to normalize whitespace and handle newlines
        parsed.original_text = Self::normalize_whitespace(&parsed.original_text);
        parsed.corrected_text = Self::normalize_whitespace(&parsed.corrected_text);

        // Post-process the result to convert markers back to newlines
        parsed.original_text = parsed.original_text.trim().replace("§NEWLINE§", "\n");
        parsed.corrected_text = parsed.corrected_text.trim().replace("§NEWLINE§", "\n");

        // Also process corrections
        for correction in &mut parsed.corrections {
            Self::process_newlines_in_correction(correction);
        }

        Ok(parsed)
    }

    fn normalize_whitespace(text: &str) -> String {
        // First, replace our newline markers with actual newlines
        let with_newlines = text.replace("§NEWLINE§", "\n");

        // Then normalize all whitespace sequences (including multiple newlines)
        // to single spaces, except preserve single newlines
        let mut result = String::with_capacity(with_newlines.len());
        let mut chars = with_newlines.chars().peekable();
        let mut in_whitespace = false;

        while let Some(c) = chars.next() {
            if c.is_whitespace() {
                if c == '\n' {
                    // Always keep newlines
                    if in_whitespace {
                        // Replace any preceding whitespace with a single newline
                        if !result.ends_with('\n') {
                            result.push('\n');
                        }
                    } else {
                        result.push('\n');
                    }
                    in_whitespace = true;
                } else if !in_whitespace {
                    // Start of a new whitespace sequence
                    result.push(' ');
                    in_whitespace = true;
                }
                // Skip other whitespace in a sequence
            } else {
                result.push(c);
                in_whitespace = false;
            }
        }

        result.trim().to_string()
    }

    fn process_newlines_in_correction(correction: &mut Correction) {
        correction.original = correction.original.replace("§NEWLINE§", "\n");
        correction.correction = correction.correction.replace("§NEWLINE§", "\n");
        if let Some(explanation) = &mut correction.explanation {
            *explanation = explanation.replace("§NEWLINE§", "\n");
        }

        // Process children recursively
        for child in &mut correction.children {
            Self::process_newlines_in_correction(child);
        }
    }

    fn get_attribute(
        e: &quick_xml::events::BytesStart,
        name: &str,
    ) -> Result<String, quick_xml::Error> {
        for attr in e.attributes() {
            let attr = attr?;
            if attr.key.as_ref() == name.as_bytes() {
                return Ok(attr.unescape_value()?.into_owned());
            }
        }
        Err(quick_xml::Error::IllFormed(
            quick_xml::errors::IllFormedError::MissingEndTag("Attribute not found".to_string()),
        ))
    }

    //  fn get_optional_attribute(e: &quick_xml::events::BytesStart, name: &str) -> Option<String> {
    //      for attr in e.attributes() {
    //          if let Ok(attr) = attr {
    //              if attr.key.as_ref() == name.as_bytes() {
    //                  if let Ok(value) = attr.unescape_value() {
    //                      return Some(value.into_owned());
    //                  }
    //              }
    //          }
    //      }
    //      None
    //  }
}

// Convenience function for simple usage
pub fn parse_xml_corrections(xml: &str) -> Result<ParsedText, ParserError> {
    let mut parser = XmlParser::new();
    parser.parse(xml)
}
