// lib.rs
use roxmltree::{Document, Node, NodeType};
use serde_json::{json, Value};
use std::error::Error;
use std::fmt;

#[derive(Debug, Clone)]
pub enum CorrectionNode {
    Text(String),
    Fix {
        original: Vec<CorrectionNode>,
        corrected: Vec<CorrectionNode>,
        explanation: Option<String>,
        children: Vec<CorrectionNode>,
    },
    Revision {
        original: Vec<CorrectionNode>,
        corrected: Vec<CorrectionNode>,
        explanation: Option<String>,
        children: Vec<CorrectionNode>,
    },
    Segment(Vec<CorrectionNode>),
}

#[derive(Debug)]
pub struct CorrectionDocument {
    pub root: Vec<CorrectionNode>,
}

#[derive(Debug)]
pub enum ParseError {
    MissingOriginal,
    MissingCorrected,
    InvalidStructure(String),
    XmlError(String),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            ParseError::MissingOriginal => write!(f, "Missing original element"),
            ParseError::MissingCorrected => write!(f, "Missing corrected element"),
            ParseError::InvalidStructure(msg) => write!(f, "Invalid structure: {}", msg),
            ParseError::XmlError(msg) => write!(f, "XML error: {}", msg),
        }
    }
}

impl Error for ParseError {}

impl CorrectionDocument {
    pub fn parse(xml: &str) -> Result<Self, Box<dyn Error>> {
        let doc = Document::parse(xml).map_err(|e| ParseError::XmlError(e.to_string()))?;
        let root = doc.root_element();

        // Find the content element - handle namespace properly
        let content = root
            .children()
            .find(|n| {
                n.is_element() &&
                n.tag_name().name() == "content" &&
                n.tag_name().namespace().map_or(false, |ns| ns.ends_with("correction-system"))
            })
            .ok_or_else(|| ParseError::InvalidStructure("Missing cor:content element".into()))?;

        let nodes = parse_nodes(content)?;
        Ok(CorrectionDocument { root: nodes })
    }

    pub fn reconstruct_original(&self) -> String {
        let mut result = String::new();
        result.push_str(&reconstruct_nodes_with_spacing(&self.root, false));
        result
    }

    pub fn reconstruct_corrected(&self) -> String {
        let mut result = String::new();
        result.push_str(&reconstruct_nodes_with_spacing(&self.root, true));
        result
    }

    pub fn find_by_explanation<'a>(&'a self, explanation: &str) -> Vec<&'a CorrectionNode> {
        self.find_nodes_by_explanation(&self.root, explanation)
    }

    fn find_nodes_by_explanation<'a>(&self, nodes: &'a [CorrectionNode],
                                   explanation: &str) -> Vec<&'a CorrectionNode> {
        let mut result = Vec::new();

        for node in nodes {
            match node {
                CorrectionNode::Fix { explanation: Some(e), children, .. } if e.contains(explanation) => {
                    result.push(node);
                    result.extend(self.find_nodes_by_explanation(children, explanation));
                }
                CorrectionNode::Revision { explanation: Some(e), children, .. } if e.contains(explanation) => {
                    result.push(node);
                    result.extend(self.find_nodes_by_explanation(children, explanation));
                }
                CorrectionNode::Fix { children, .. } |
                CorrectionNode::Revision { children, .. } => {
                    result.extend(self.find_nodes_by_explanation(children, explanation));
                }
                CorrectionNode::Segment(children) => {
                    result.extend(self.find_nodes_by_explanation(children, explanation));
                }
                _ => {}
            }
        }

        result
    }

    pub fn to_json(&self) -> Value {
        json!({
            "root": nodes_to_json(&self.root),
            "original": self.reconstruct_original(),
            "corrected": self.reconstruct_corrected()
        })
    }
}

fn nodes_to_json(nodes: &[CorrectionNode]) -> Value {
    let mut result = Vec::new();

    for node in nodes {
        match node {
            CorrectionNode::Text(text) => {
                result.push(json!({
                    "type": "text",
                    "content": text
                }));
            }
            CorrectionNode::Fix { original, corrected, explanation, children } => {
                result.push(json!({
                    "type": "fix",
                    "explanation": explanation,
                    "original": nodes_to_json(original),
                    "corrected": nodes_to_json(corrected),
                    "children": nodes_to_json(children)
                }));
            }
            CorrectionNode::Revision { original, corrected, explanation, children } => {
                result.push(json!({
                    "type": "revision",
                    "explanation": explanation,
                    "original": nodes_to_json(original),
                    "corrected": nodes_to_json(corrected),
                    "children": nodes_to_json(children)
                }));
            }
            CorrectionNode::Segment(children) => {
                result.push(json!({
                    "type": "segment",
                    "children": nodes_to_json(children)
                }));
            }
        }
    }

    json!(result)
}

// Helper function to check if a node has a specific tag in the correction namespace
fn has_correction_tag(node: &Node, tag_name: &str) -> bool {
    node.is_element() &&
    node.tag_name().name() == tag_name &&
    node.tag_name().namespace().map_or(false, |ns| ns.ends_with("correction-system"))
}

// Strip all whitespace from text
fn strip_whitespace(text: &str) -> String {
    text.chars().filter(|c| !c.is_whitespace()).collect()
}

// Parse nodes - fix the warning about unused tag_name
fn parse_nodes(node: Node) -> Result<Vec<CorrectionNode>, Box<dyn Error>> {
    let mut nodes = Vec::new();

    for child in node.children() {
        match child.node_type() {
            NodeType::Text => {
                let text = child.text().unwrap_or("").to_string();
                // Only add text that has non-whitespace content
                if !text.trim().is_empty() {
                    // Strip all whitespace completely
                    let stripped = strip_whitespace(&text);
                    if !stripped.is_empty() {
                        nodes.push(CorrectionNode::Text(stripped));
                    }
                }
            }
            NodeType::Element => {
                let _tag_name = child.tag_name().name(); // Fixed unused variable warning

                if has_correction_tag(&child, "fix") {
                    let explanation = child.attribute("explanation").map(String::from);

                    // Find original and corrected elements
                    let original = child
                        .children()
                        .find(|n| has_correction_tag(n, "original"))
                        .ok_or(ParseError::MissingOriginal)?;

                    let corrected = child
                        .children()
                        .find(|n| has_correction_tag(n, "corrected"))
                        .ok_or(ParseError::MissingCorrected)?;

                    let original_nodes = parse_nodes(original)?;
                    let corrected_nodes = parse_nodes(corrected)?;

                    // Parse nested corrections
                    let mut children = Vec::new();
                    for nested in child.children() {
                        if nested.is_element() &&
                           !has_correction_tag(&nested, "original") &&
                           !has_correction_tag(&nested, "corrected") {
                            let nested_nodes = parse_nodes(nested)?;
                            children.extend(nested_nodes);
                        }
                    }

                    nodes.push(CorrectionNode::Fix {
                        original: original_nodes,
                        corrected: corrected_nodes,
                        explanation,
                        children,
                    });
                } else if has_correction_tag(&child, "revision") {
                    let explanation = child.attribute("explanation").map(String::from);

                    let original = child
                        .children()
                        .find(|n| has_correction_tag(n, "original"))
                        .ok_or(ParseError::MissingOriginal)?;

                    let corrected = child
                        .children()
                        .find(|n| has_correction_tag(n, "corrected"))
                        .ok_or(ParseError::MissingCorrected)?;

                    let original_nodes = parse_nodes(original)?;
                    let corrected_nodes = parse_nodes(corrected)?;

                    // Parse nested corrections
                    let mut children = Vec::new();
                    for nested in child.children() {
                        if nested.is_element() &&
                           !has_correction_tag(&nested, "original") &&
                           !has_correction_tag(&nested, "corrected") {
                            let nested_nodes = parse_nodes(nested)?;
                            children.extend(nested_nodes);
                        }
                    }

                    nodes.push(CorrectionNode::Revision {
                        original: original_nodes,
                        corrected: corrected_nodes,
                        explanation,
                        children,
                    });
                } else if has_correction_tag(&child, "segment") {
                    let segment_nodes = parse_nodes(child)?;
                    if !segment_nodes.is_empty() {
                        nodes.push(CorrectionNode::Segment(segment_nodes));
                    }
                } else if has_correction_tag(&child, "original") || has_correction_tag(&child, "corrected") {
                    // These are handled by their parent elements
                    let nested_nodes = parse_nodes(child)?;
                    nodes.extend(nested_nodes);
                } else if has_correction_tag(&child, "br") {
                    // Special handling for line break tags
                    nodes.push(CorrectionNode::Text("\n".to_string()));
                } else {
                    // Process other elements
                    let nested_nodes = parse_nodes(child)?;
                    nodes.extend(nested_nodes);
                }
            }
            _ => {}
        }
    }

    Ok(nodes)
}

// Completely revised reconstruction functions
fn reconstruct_node(node: &CorrectionNode, use_corrected: bool) -> String {
    match node {
        CorrectionNode::Text(text) => text.clone(),
        CorrectionNode::Fix { original, corrected, children, .. } => {
            let mut result = String::new();

            // Use either original or corrected based on the flag
            let nodes = if use_corrected { corrected } else { original };

            // Add the content with proper spacing
            if !nodes.is_empty() {
                result.push_str(&reconstruct_nodes_with_spacing(nodes, use_corrected));
            }

            // Add children content only if they're not part of original/corrected
            if !children.is_empty() {
                if !result.is_empty() && !result.ends_with(' ') && !result.ends_with('\n') {
                    result.push(' ');
                }
                result.push_str(&reconstruct_nodes_with_spacing(children, use_corrected));
            }

            result
        }
        CorrectionNode::Revision { original, corrected, children, .. } => {
            let mut result = String::new();

            // Use either original or corrected based on the flag
            let nodes = if use_corrected { corrected } else { original };

            // Add the content with proper spacing
            if !nodes.is_empty() {
                result.push_str(&reconstruct_nodes_with_spacing(nodes, use_corrected));
            }

            // Add children content only if they're not part of original/corrected
            if !children.is_empty() {
                if !result.is_empty() && !result.ends_with(' ') && !result.ends_with('\n') {
                    result.push(' ');
                }
                result.push_str(&reconstruct_nodes_with_spacing(children, use_corrected));
            }

            result
        }
        CorrectionNode::Segment(children) => {
            reconstruct_nodes_with_spacing(children, use_corrected)
        }
    }
}


// A smarter function that properly handles spacing between nodes
fn reconstruct_nodes_with_spacing(nodes: &[CorrectionNode], use_corrected: bool) -> String {
    if nodes.is_empty() {
        return String::new();
    }

    let mut result = String::new();

    for (i, node) in nodes.iter().enumerate() {
        let node_text = match node {
            CorrectionNode::Text(text) => text.clone(),
            _ => reconstruct_node(node, use_corrected),
        };

        // Skip empty nodes
        if node_text.is_empty() {
            continue;
        }

        // Add space before this node if needed
        if i > 0 && !node_text.is_empty() {
            let prev_text = result.chars().last();
            let current_first = node_text.chars().next();

            let need_space = match (prev_text, current_first) {
                // No space after these characters
                (Some('('), _) | (Some('['), _) | (Some('{'), _) | (Some(' '), _) |
                (Some('\n'), _) | (Some('*'), _) | (Some('"'), _) | (Some('\''), _) => false,

                // No space before these characters
                (_, Some(')')) | (_, Some(']')) | (_, Some('}')) | (_, Some('.')) |
                (_, Some(',')) | (_, Some(';')) | (_, Some(':')) | (_, Some('!')) |
                (_, Some('?')) | (_, Some('*')) | (_, Some('"')) | (_, Some('\'')) => false,

                // Otherwise, add space between words
                (Some(_), Some(_)) => true,

                // Handle null cases
                _ => false,
            };

            if need_space {
                result.push(' ');
            }
        }

        // Add the node text
        result.push_str(&node_text);
    }

    result
}
