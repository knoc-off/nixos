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

    pub fn parse(&mut self, xml: &str) -> Result<ParsedText, ParserError> {
        let mut reader = Reader::from_str(xml);
        // Configure the reader to trim whitespace
        reader.config_mut().trim_text_start = true;
        reader.config_mut().trim_text_end = true;

        let mut parsed = ParsedText {
            original_text: String::new(),
            corrected_text: String::new(),
            corrections: Vec::new(),
            suggestions: None,
        };

        let mut buf = Vec::with_capacity(self.buffer_size);
        let mut stack = VecDeque::new();
        let mut current_correction: Option<Correction> = None;
        let mut current_text = String::new();
        let mut in_element: Option<String> = None;

        loop {
            match reader.read_event_into(&mut buf) {
                Ok(Event::Start(e)) => {
                    let name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                    match name.as_str() {
                        "correction" => {
                            let error_type = Self::get_attribute(&e, "type").map_err(|e| {
                                ParserError::AttributeError(format!("Error getting 'type' attribute: {}", e))
                            })?;

                            let explanation = Self::get_optional_attribute(&e, "explanation");

                            let correction = Correction {
                                error_type,
                                explanation,
                                original: String::new(),
                                correction: String::new(),
                                children: Vec::new(),
                            };

                            if let Some(parent) = current_correction.take() {
                                stack.push_back(parent);
                            }
                            current_correction = Some(correction);
                        }
                        "original" | "corrected" | "suggestions" | "content" => {
                            in_element = Some(name);
                            current_text.clear();
                        }
                        _ => {}
                    }
                }

                Ok(Event::End(e)) => {
                    let name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                    match name.as_str() {
                        "correction" => {
                            let mut correction = current_correction
                                .take()
                                .ok_or(ParserError::InvalidStructure("Unmatched correction end tag"))?;

                            // If original or correction is empty, use the other value
                            if correction.original.is_empty() && !correction.correction.is_empty() {
                                correction.original = correction.correction.clone();
                            } else if correction.correction.is_empty() && !correction.original.is_empty() {
                                correction.correction = correction.original.clone();
                            }

                            // Handle text reconstruction
                            if stack.is_empty() {
                                parsed.original_text.push_str(&correction.original);
                                parsed.corrected_text.push_str(&correction.correction);
                            }

                            if let Some(mut parent) = stack.pop_back() {
                                parent.children.push(correction);
                                current_correction = Some(parent);
                            } else {
                                parsed.corrections.push(correction);
                            }
                        }

                        "original" => {
                            if let Some(correction) = &mut current_correction {
                                correction.original = current_text.trim().to_string();
                            }
                            in_element = None;
                        }

                        "corrected" => {
                            if let Some(correction) = &mut current_correction {
                                correction.correction = current_text.trim().to_string();
                            }
                            in_element = None;
                        }

                        "suggestions" => {
                            parsed.suggestions = Some(current_text.trim().to_string());
                            in_element = None;
                        }

                        "content" => {
                            in_element = None;
                        }

                        _ => {}
                    }
                    current_text.clear();
                }

                Ok(Event::Text(e)) => {
                    let text = e.unescape().map_err(ParserError::XmlError)?.into_owned();

                    // Skip pure whitespace text nodes
                    if text.trim().is_empty() {
                        continue;
                    }

                    match &in_element {
                        Some(element)
                            if element == "original" || element == "corrected" || element == "suggestions" =>
                        {
                            current_text.push_str(&text);
                        }
                        Some(element) if element == "content" => {
                            if current_correction.is_none() {
                                // For content outside of corrections, add to both original and corrected
                                let trimmed = text.trim();
                                if !trimmed.is_empty() {
                                    parsed.original_text.push_str(trimmed);
                                    parsed.corrected_text.push_str(trimmed);

                                    // Add a space if this isn't the first text and doesn't end with punctuation
                                    if !parsed.original_text.is_empty() &&
                                       !parsed.original_text.ends_with(|c: char| c.is_whitespace() || c.is_ascii_punctuation()) &&
                                       !trimmed.starts_with(|c: char| c.is_whitespace() || c.is_ascii_punctuation()) {
                                        parsed.original_text.push(' ');
                                        parsed.corrected_text.push(' ');
                                    }
                                }
                            }
                            current_text.push_str(&text);
                        }
                        _ => {
                            if current_correction.is_none() {
                                // For text outside of any element, add to both original and corrected
                                let trimmed = text.trim();
                                if !trimmed.is_empty() {
                                    parsed.original_text.push_str(trimmed);
                                    parsed.corrected_text.push_str(trimmed);

                                    // Add a space if this isn't the first text and doesn't end with punctuation
                                    if !parsed.original_text.is_empty() &&
                                       !parsed.original_text.ends_with(|c: char| c.is_whitespace() || c.is_ascii_punctuation()) &&
                                       !trimmed.starts_with(|c: char| c.is_whitespace() || c.is_ascii_punctuation()) {
                                        parsed.original_text.push(' ');
                                        parsed.corrected_text.push(' ');
                                    }
                                }
                            }
                        }
                    }
                }

                Ok(Event::Eof) => break,
                Err(e) => return Err(ParserError::XmlError(e)),
                _ => {}
            }

            buf.clear();
        }

        // Final cleanup of any extra whitespace
        parsed.original_text = parsed.original_text.trim().to_string();
        parsed.corrected_text = parsed.corrected_text.trim().to_string();

        Ok(parsed)
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
        Err(quick_xml::Error::IllFormed(quick_xml::errors::IllFormedError::MissingEndTag("Attribute not found".to_string())))
    }

    fn get_optional_attribute(e: &quick_xml::events::BytesStart, name: &str) -> Option<String> {
        for attr in e.attributes() {
            if let Ok(attr) = attr {
                if attr.key.as_ref() == name.as_bytes() {
                    if let Ok(value) = attr.unescape_value() {
                        return Some(value.into_owned());
                    }
                }
            }
        }
        None
    }
}

// Convenience function for simple usage
pub fn parse_xml_corrections(xml: &str) -> Result<ParsedText, ParserError> {
    let mut parser = XmlParser::new();
    parser.parse(xml)
}
