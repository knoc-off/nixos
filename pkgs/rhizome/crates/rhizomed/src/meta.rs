//! The editable metadata pop-out's on-disk format: title plus labels and
//! relations, as YAML.
//!
//! An earlier version of this format was deliberately not YAML, on the
//! grounds that Trilium attribute values are always strings and YAML's type
//! coercion (`#draft=yes` -> boolean `true`, `version: 1.10` -> float `1.1`)
//! would silently corrupt them. That objection is correct about a *naive*
//! YAML stack (parse into a typed `Value`, stringify back) but not about
//! this one: `marked_yaml::Node::Scalar` always holds the source string
//! exactly as written, with no type resolution at all, so `year: 1992`
//! parses back as the string `"1992"` whether or not it is quoted. The
//! coercion this format existed to avoid cannot happen here by construction,
//! which is also why `render` does not need to quote a value just because
//! it looks like a number or a boolean -- only when the bytes would
//! otherwise be invalid or ambiguous YAML syntax (see `quote_scalar`).
//!
//! `marked_yaml` also refuses non-scalar mapping keys and requires a mapping
//! at the document root, and attaches a source `Span` to every node -- all
//! properties this format leans on for validation and, eventually,
//! diagnostics with real cursor positions.
//!
//! Render, parse and diff are kept separate from anything that talks to
//! Trilium, so the format can be tested without a server.

use marked_yaml::{LoadError, Marker, Node, Span};

use rhizome_etapi::{Attribute, Note};

/// Attribute names Trilium maintains for its own bookkeeping (link scanning,
/// includes, bookmarks). Never shown, never editable: round-tripping them
/// naively would mean deleting relations `scanForLinks` immediately
/// recreates on the very next content write, on every save.
const SYSTEM_RELATIONS: &[&str] = &[
    "internalLink",
    "imageLink",
    "includeNoteLink",
    "relationMapLink",
    "internalBookmark",
];

fn is_system(attribute: &Attribute) -> bool {
    attribute.is_relation() && SYSTEM_RELATIONS.contains(&attribute.name.as_str())
}

/// Whether `attribute` is one Trilium maintains for its own bookkeeping --
/// exposed for `index::vocabulary`, which must not offer these as
/// completions any more than the metadata pop-out shows them as fields.
pub(crate) fn is_system_relation(attribute: &Attribute) -> bool {
    is_system(attribute)
}

/// A single label or relation instance. Trilium attributes are multivalued
/// -- two `#genre` labels can coexist on one note -- so a name can appear as
/// more than one `Field` with the same `kind`/`name`; see `render` for how
/// that is written and `plan` for how it is diffed.
#[derive(Debug, Clone)]
pub struct Field {
    pub kind: Kind,
    pub name: String,
    pub value: String,
    pub inheritable: bool,
    /// 1-based `(line, column)` of the value in the buffer `parse` read
    /// this from, if it came from one -- `None` for a `Field` built by hand
    /// (e.g. `Metadata::from_note`, or in tests). Used only to anchor
    /// diagnostics at the right line; carries no data of its own, so it is
    /// excluded from equality -- two fields the user typed identically are
    /// the same field whether or not one of them moved.
    pub at: Option<(usize, usize)>,
}

impl PartialEq for Field {
    fn eq(&self, other: &Self) -> bool {
        self.kind == other.kind
            && self.name == other.name
            && self.value == other.value
            && self.inheritable == other.inheritable
    }
}

impl Eq for Field {}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Kind {
    Label,
    Relation,
}

/// What the pop-out shows and what it can hand back to be applied.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Metadata {
    pub note_id: String,
    pub note_type: String,
    pub title: String,
    pub fields: Vec<Field>,
}

impl Metadata {
    pub fn from_note(note: &Note) -> Self {
        let fields = note
            .attributes
            .iter()
            .filter(|a| !is_system(a))
            .map(|a| Field {
                kind: if a.is_relation() {
                    Kind::Relation
                } else {
                    Kind::Label
                },
                name: a.name.clone(),
                value: a.value.clone(),
                inheritable: a.is_inheritable,
                at: None,
            })
            .collect();
        Metadata {
            note_id: note.note_id.clone(),
            note_type: note.note_type.clone(),
            title: note.title.clone(),
            fields,
        }
    }
}

/// Quote a scalar only if its literal bytes would otherwise be invalid or
/// ambiguous YAML, never to prevent type coercion (there is none to
/// prevent -- see the module docs). This deliberately under-quotes relative
/// to a generic YAML emitter: the common case (a plain word, a name, a
/// bare number) is far more pleasant to type and to read unquoted, and nothing
/// here depends on the emitted form being type-preserving.
fn quote_scalar(s: &str) -> String {
    let needs_quoting = s.is_empty()
        || s.contains('\n')
        || s.contains('\t')
        || s.starts_with(' ')
        || s.ends_with(' ')
        || s.ends_with(':')
        || s.contains(": ")
        || s.contains(" #")
        || s.starts_with(|c: char| "-?:,[]{}#&*!|>'\"%@`".contains(c));
    if !needs_quoting {
        return s.to_string();
    }
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

/// One name's values as `render` groups them: every `Field` sharing a
/// `kind`/`name`, in the order they appeared on the note.
struct Group<'a> {
    name: &'a str,
    fields: Vec<&'a Field>,
}

fn grouped(fields: &[Field], kind: Kind) -> Vec<Group<'_>> {
    let mut groups: Vec<Group> = Vec::new();
    for field in fields.iter().filter(|f| f.kind == kind) {
        match groups.iter_mut().find(|g| g.name == field.name) {
            Some(g) => g.fields.push(field),
            None => groups.push(Group {
                name: &field.name,
                fields: vec![field],
            }),
        }
    }
    groups
}

/// Render one value: a bare scalar if not inheritable, an inline `{value:
/// ..., inheritable: true}` mapping otherwise. A value-less label (`value`
/// is empty and not inheritable) renders as nothing at all after the colon,
/// an explicit empty YAML scalar, rather than `""`, so the common case of
/// tagging a note with a bare `#todo` stays a one-token line.
fn render_value(field: &Field) -> String {
    if field.inheritable {
        format!(
            "{{value: {}, inheritable: true}}",
            quote_scalar(&field.value)
        )
    } else if field.value.is_empty() {
        String::new()
    } else {
        quote_scalar(&field.value)
    }
}

/// Always renders the header, even with nothing under it -- `section_of` in
/// `lsp/text.rs` anchors completion by scanning upward for exactly this
/// line, so a note with no labels yet would otherwise have no `labels:` to
/// complete under at all.
fn render_section(out: &mut String, heading: &str, groups: &[Group]) {
    out.push('\n');
    out.push_str(heading);
    out.push_str(":\n");
    for group in groups {
        if group.fields.len() == 1 {
            let value = render_value(group.fields[0]);
            if value.is_empty() {
                out.push_str(&format!("  {}:\n", group.name));
            } else {
                out.push_str(&format!("  {}: {}\n", group.name, value));
            }
        } else {
            out.push_str(&format!("  {}:\n", group.name));
            for field in &group.fields {
                let value = render_value(field);
                let item = if value.is_empty() {
                    "\"\"".to_string()
                } else {
                    value
                };
                out.push_str(&format!("    - {item}\n"));
            }
        }
    }
}

pub fn render(meta: &Metadata) -> String {
    let mut out = String::new();
    // A guide line above the data, not inside it -- `section_of` in
    // `lsp/text.rs` bails at the first non-indented, non-empty line it
    // meets scanning upward for a section header, so a comment anywhere
    // inside `labels:`/`relations:` would break completion for every entry
    // above it. Above `title:` is the only place that is always safe: any
    // upward scan from inside a section hits that section's own header
    // line first, never reaching this far. Emitted by `render` itself, so
    // `:w` restores it even if edited or deleted -- it carries no data, so
    // there is nothing for that to lose.
    out.push_str("# :w apply | q close | g? help\n");
    out.push_str(&format!("title: {}\n", quote_scalar(&meta.title)));
    out.push_str(&format!("noteId: {}\n", meta.note_id));
    out.push_str(&format!("type: {}\n", meta.note_type));
    render_section(&mut out, "labels", &grouped(&meta.fields, Kind::Label));
    render_section(
        &mut out,
        "relations",
        &grouped(&meta.fields, Kind::Relation),
    );
    out
}

/// A parse or validation failure, with the 1-based `(line, column)` of the
/// offending text when a specific node is to blame -- `None` only for the
/// handful of whole-document errors (a missing top-level key has no single
/// node to point at).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError {
    pub message: String,
    pub at: Option<(usize, usize)>,
}

impl ParseError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            at: None,
        }
    }

    fn at_marker(message: impl Into<String>, marker: &Marker) -> Self {
        Self {
            message: message.into(),
            at: Some((marker.line(), marker.column())),
        }
    }

    fn at_span(message: impl Into<String>, span: &Span) -> Self {
        match span.start() {
            Some(marker) => Self::at_marker(message, marker),
            None => Self::new(message),
        }
    }
}

/// The `Marker` a `LoadError` carries, regardless of which variant fired --
/// every one but `DuplicateKey` wraps a bare `Marker` directly.
fn marker_of(error: &LoadError) -> Option<Marker> {
    use LoadError::*;
    match error {
        TopLevelMustBeMapping(m)
        | TopLevelMustBeSequence(m)
        | UnexpectedAnchor(m)
        | MappingKeyMustBeScalar(m)
        | UnexpectedTag(m)
        | ScanError(m, _) => Some(*m),
        DuplicateKey(inner) => inner.key.span().start().copied(),
    }
}

/// A span's starting `(line, column)`, 1-based, for `Field::at` -- `None`
/// only if the span itself carries no position, which `marked_yaml` never
/// actually produces for a node parsed from text.
fn marker_pos(span: &Span) -> Option<(usize, usize)> {
    span.start().map(|m| (m.line(), m.column()))
}

fn field_from_node(kind: Kind, name: &str, node: &Node) -> Result<Field, ParseError> {
    match node {
        Node::Scalar(s) => Ok(Field {
            kind,
            name: name.to_string(),
            value: s.as_str().to_string(),
            inheritable: false,
            at: marker_pos(s.span()),
        }),
        Node::Mapping(m) => {
            let value_node = m.get_scalar("value");
            let value = value_node
                .map(|s| s.as_str().to_string())
                .unwrap_or_default();
            let inheritable = match m.get_scalar("inheritable") {
                None => false,
                Some(s) => match s.as_str() {
                    "true" => true,
                    "false" => false,
                    other => {
                        return Err(ParseError::at_span(
                            format!("'{name}.inheritable' must be true or false, got '{other}'"),
                            s.span(),
                        ));
                    }
                },
            };
            Ok(Field {
                kind,
                name: name.to_string(),
                value,
                inheritable,
                at: value_node
                    .and_then(|s| marker_pos(s.span()))
                    .or_else(|| marker_pos(node.span())),
            })
        }
        Node::Sequence(seq) => Err(ParseError::at_span(
            format!("'{name}' cannot contain a nested list"),
            seq.span(),
        )),
    }
}

fn extract_fields(kind: Kind, name: &str, node: &Node) -> Result<Vec<Field>, ParseError> {
    match node {
        Node::Sequence(seq) => seq
            .iter()
            .map(|item| field_from_node(kind, name, item))
            .collect(),
        other => Ok(vec![field_from_node(kind, name, other)?]),
    }
}

fn section_fields(
    top: &marked_yaml::types::MarkedMappingNode,
    key: &str,
    kind: Kind,
) -> Result<Vec<Field>, ParseError> {
    let Some(node) = top.get(key) else {
        return Ok(Vec::new());
    };
    // `render` always emits the header now, even with nothing under it --
    // which YAML loads as a null scalar, not a mapping, since there is
    // nothing after the colon. That is the ordinary empty case, not a
    // malformed document.
    if let Node::Scalar(s) = node
        && s.as_str().is_empty()
    {
        return Ok(Vec::new());
    }
    let Node::Mapping(section) = node else {
        return Err(ParseError::at_span(
            format!("'{key}' must be a mapping"),
            node.span(),
        ));
    };
    let mut fields = Vec::new();
    for (name, value) in section.iter() {
        fields.extend(extract_fields(kind, name.as_str(), value)?);
    }
    Ok(fields)
}

/// Parse the pop-out's text back into `Metadata`. `note_id` and `note_type`
/// are read but not trusted from the buffer -- see `plan`, which refuses to
/// apply a document whose id or type has been edited, since neither is
/// something a save here can actually change.
pub fn parse(text: &str) -> Result<Metadata, ParseError> {
    let node = marked_yaml::parse_yaml(0, text).map_err(|e| {
        let message = e.to_string();
        match marker_of(&e) {
            Some(marker) => ParseError::at_marker(message, &marker),
            None => ParseError::new(message),
        }
    })?;
    let Node::Mapping(top) = &node else {
        return Err(ParseError::at_span(
            "document must be a mapping",
            node.span(),
        ));
    };

    for (key, _) in top.iter() {
        if !matches!(
            key.as_str(),
            "title" | "noteId" | "type" | "labels" | "relations"
        ) {
            return Err(ParseError::at_span(
                format!(
                    "unknown top-level key '{}'; expected 'title', 'noteId', 'type', 'labels' or 'relations'",
                    key.as_str()
                ),
                key.span(),
            ));
        }
    }

    let title = top
        .get_scalar("title")
        .ok_or_else(|| ParseError::new("missing 'title' key"))?
        .as_str()
        .to_string();
    let note_type = top
        .get_scalar("type")
        .ok_or_else(|| ParseError::new("missing 'type' key"))?
        .as_str()
        .to_string();
    let note_id = top
        .get_scalar("noteId")
        .ok_or_else(|| ParseError::new("missing 'noteId' key"))?
        .as_str()
        .to_string();

    let mut fields = section_fields(top, "labels", Kind::Label)?;
    fields.extend(section_fields(top, "relations", Kind::Relation)?);

    Ok(Metadata {
        note_id,
        note_type,
        title,
        fields,
    })
}

/// A single ETAPI call needed to make a note's attributes match `desired`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Change {
    Rename(String),
    Set {
        /// `Some` updates that exact attribute in place, keeping its
        /// `attributeId` and Trilium's own change history for it. `None`
        /// creates a new attribute -- there is no existing instance at this
        /// position to reuse, which is exactly the case a multivalued
        /// label gains an extra value.
        attribute_id: Option<String>,
        kind: Kind,
        name: String,
        value: String,
        inheritable: bool,
    },
    Remove {
        attribute_id: String,
    },
}

/// The minimal set of changes to turn `current` into `desired`. Diff-based
/// rather than delete-and-recreate, so an untouched attribute keeps its
/// `attributeId` and Trilium's own change history for it, and so this does
/// not spuriously touch attributes the pop-out never showed (the filtered
/// system relations).
///
/// Matching within a `(kind, name)` group is positional: a note's existing
/// `#genre` values line up with the pop-out's `genre` list index for index,
/// since Trilium attributes are multivalued and there is no other stable key
/// to match repeated values by. Reordering a multivalued list's items is
/// therefore read as replacing them, same as editing any of their values.
pub fn plan(current: &Note, desired: &Metadata) -> Result<Vec<Change>, ParseError> {
    if desired.note_id != current.note_id {
        return Err(ParseError::new(
            "noteId cannot be changed from the metadata pop-out",
        ));
    }
    if desired.note_type != current.note_type {
        return Err(ParseError::new(
            "type cannot be changed from the metadata pop-out",
        ));
    }

    let mut changes = Vec::new();
    if desired.title != current.title {
        changes.push(Change::Rename(desired.title.clone()));
    }

    let editable: Vec<&Attribute> = current
        .attributes
        .iter()
        .filter(|a| !is_system(a))
        .collect();

    let mut names: Vec<(Kind, &str)> = Vec::new();
    for attribute in &editable {
        let kind = if attribute.is_relation() {
            Kind::Relation
        } else {
            Kind::Label
        };
        if !names.iter().any(|&(k, n)| k == kind && n == attribute.name) {
            names.push((kind, attribute.name.as_str()));
        }
    }
    for field in &desired.fields {
        if !names
            .iter()
            .any(|&(k, n)| k == field.kind && n == field.name)
        {
            names.push((field.kind, field.name.as_str()));
        }
    }

    for (kind, name) in names {
        let current_instances: Vec<&Attribute> = editable
            .iter()
            .filter(|a| {
                a.name == name
                    && matches!(
                        (kind, a.is_relation()),
                        (Kind::Relation, true) | (Kind::Label, false)
                    )
            })
            .copied()
            .collect();
        let desired_instances: Vec<&Field> = desired
            .fields
            .iter()
            .filter(|f| f.kind == kind && f.name == name)
            .collect();

        let paired = current_instances.len().min(desired_instances.len());
        for i in 0..paired {
            let existing = current_instances[i];
            let field = desired_instances[i];
            if existing.value != field.value || existing.is_inheritable != field.inheritable {
                changes.push(Change::Set {
                    attribute_id: Some(existing.attribute_id.clone()),
                    kind,
                    name: name.to_string(),
                    value: field.value.clone(),
                    inheritable: field.inheritable,
                });
            }
        }
        for field in &desired_instances[paired..] {
            changes.push(Change::Set {
                attribute_id: None,
                kind,
                name: name.to_string(),
                value: field.value.clone(),
                inheritable: field.inheritable,
            });
        }
        for existing in &current_instances[paired..] {
            changes.push(Change::Remove {
                attribute_id: existing.attribute_id.clone(),
            });
        }
    }

    Ok(changes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(attributes: Vec<Attribute>) -> Note {
        Note {
            note_id: "abc123".into(),
            title: "My Note".into(),
            note_type: "text".into(),
            mime: "text/html".into(),
            blob_id: "x".into(),
            is_protected: false,
            parent_note_ids: vec![],
            child_note_ids: vec![],
            attributes,
            date_modified: None,
        }
    }

    fn label(name: &str, value: &str) -> Attribute {
        Attribute {
            attribute_id: format!("attr-{name}-{value}"),
            note_id: "abc123".into(),
            attribute_type: "label".into(),
            name: name.into(),
            value: value.into(),
            is_inheritable: false,
        }
    }

    fn relation(name: &str, target: &str) -> Attribute {
        Attribute {
            attribute_id: format!("attr-{name}"),
            note_id: "abc123".into(),
            attribute_type: "relation".into(),
            name: name.into(),
            value: target.into(),
            is_inheritable: false,
        }
    }

    #[test]
    fn renders_title_type_id_and_fields() {
        let note = note(vec![label("todo", ""), relation("template", "tpl1")]);
        let text = render(&Metadata::from_note(&note));
        assert!(text.contains("title: My Note"));
        assert!(text.contains("noteId: abc123"));
        assert!(text.contains("type: text"));
        assert!(text.contains("todo:\n"), "{text}");
        assert!(text.contains("template: tpl1"));
    }

    #[test]
    fn renders_a_guide_comment_above_the_data() {
        let text = render(&Metadata::from_note(&note(vec![])));
        assert!(text.starts_with("# "), "{text}");
    }

    #[test]
    fn renders_empty_sections_as_bare_headers_so_completion_has_something_to_anchor_to() {
        let text = render(&Metadata::from_note(&note(vec![])));
        assert!(text.contains("\nlabels:\n"), "{text}");
        assert!(text.contains("\nrelations:\n"), "{text}");
    }

    #[test]
    fn a_document_with_no_labels_or_relations_round_trips() {
        let meta = Metadata::from_note(&note(vec![]));
        let text = render(&meta);
        assert_eq!(parse(&text).unwrap(), meta);
    }

    #[test]
    fn system_relations_are_never_rendered() {
        let note = note(vec![relation("internalLink", "other1")]);
        let text = render(&Metadata::from_note(&note));
        assert!(!text.contains("internalLink"));
    }

    #[test]
    fn parses_its_own_output_back() {
        let note = note(vec![label("priority", "3"), relation("template", "tpl1")]);
        let meta = Metadata::from_note(&note);
        let text = render(&meta);
        assert_eq!(parse(&text).unwrap(), meta);
    }

    /// 1-based `(line, column)` of the byte offset in `text`, computed
    /// independently of `field_from_node`/`marker_pos` -- what the test
    /// below checks `Field::at` against.
    fn line_col(text: &str, byte_offset: usize) -> (usize, usize) {
        let mut line = 1;
        let mut col = 1;
        for ch in text[..byte_offset].chars() {
            if ch == '\n' {
                line += 1;
                col = 1;
            } else {
                col += 1;
            }
        }
        (line, col)
    }

    #[test]
    fn parsed_fields_carry_the_line_their_value_is_on() {
        let note = note(vec![
            label("priority", "3"),
            label("genre", "sci-fi"),
            label("genre", "cyberpunk"),
        ]);
        let text = render(&Metadata::from_note(&note));
        let parsed = parse(&text).unwrap();

        let priority = parsed.fields.iter().find(|f| f.name == "priority").unwrap();
        let value_offset = text.rfind(": 3").unwrap() + 2;
        assert_eq!(priority.at, Some(line_col(&text, value_offset)));

        // Both `genre` values live on their own `    - value` line, not the
        // `  genre:` header's -- exactly the case that made diagnostics land
        // on line 1 no matter which item was wrong.
        let sci_fi = parsed
            .fields
            .iter()
            .find(|f| f.name == "genre" && f.value == "sci-fi")
            .unwrap();
        let cyberpunk = parsed
            .fields
            .iter()
            .find(|f| f.name == "genre" && f.value == "cyberpunk")
            .unwrap();
        assert_eq!(
            sci_fi.at,
            Some(line_col(&text, text.find("sci-fi").unwrap()))
        );
        assert_eq!(
            cyberpunk.at,
            Some(line_col(&text, text.find("cyberpunk").unwrap()))
        );
        assert_ne!(sci_fi.at.unwrap().0, priority.at.unwrap().0);
    }

    #[test]
    fn a_fields_position_is_not_part_of_its_identity() {
        // `plan` diffs `desired.fields` against the note's current
        // attributes by value, not by where in the buffer they were typed
        // -- two fields alike in everything but `at` must compare equal, or
        // reordering a note's own labels would read as every one of them
        // changing.
        let a = Field {
            kind: Kind::Label,
            name: "todo".into(),
            value: "".into(),
            inheritable: false,
            at: Some((3, 3)),
        };
        let b = Field {
            at: Some((9, 1)),
            ..a.clone()
        };
        assert_eq!(a, b);
    }

    #[test]
    fn inheritable_round_trips() {
        let mut a = label("shared", "x");
        a.is_inheritable = true;
        let note = note(vec![a]);
        let meta = Metadata::from_note(&note);
        let text = render(&meta);
        assert!(text.contains("inheritable: true"));
        assert_eq!(parse(&text).unwrap(), meta);
    }

    #[test]
    fn multivalued_label_round_trips() {
        let note = note(vec![label("genre", "sci-fi"), label("genre", "cyberpunk")]);
        let meta = Metadata::from_note(&note);
        let text = render(&meta);
        assert!(text.contains("- sci-fi"), "{text}");
        assert!(text.contains("- cyberpunk"), "{text}");
        assert_eq!(parse(&text).unwrap(), meta);
    }

    /// The whole reason to prefer `marked_yaml` here: it never resolves a
    /// scalar's type, so a value that looks like a bool or a float is never
    /// silently coerced away from the string Trilium actually stores.
    #[test]
    fn numeric_and_boolean_looking_values_stay_strings() {
        let text = "title: x\nnoteId: a\ntype: text\n\nlabels:\n  year: 1992\n  draft: yes\n  ratio: 1.10\n";
        let meta = parse(text).unwrap();
        let year = meta.fields.iter().find(|f| f.name == "year").unwrap();
        let draft = meta.fields.iter().find(|f| f.name == "draft").unwrap();
        let ratio = meta.fields.iter().find(|f| f.name == "ratio").unwrap();
        assert_eq!(year.value, "1992");
        assert_eq!(draft.value, "yes");
        assert_eq!(ratio.value, "1.10");
    }

    #[test]
    fn rejects_an_unknown_top_level_key() {
        let err = parse("title: x\nnoteId: a\ntype: text\nnonsense: y\n").unwrap_err();
        assert!(
            err.message.contains("unknown top-level key"),
            "{}",
            err.message
        );
        assert_eq!(err.at, Some((4, 1)), "{err:?}");
    }

    #[test]
    fn rejects_a_non_mapping_labels_section() {
        let err = parse("title: x\nnoteId: a\ntype: text\nlabels: nope\n").unwrap_err();
        assert!(
            err.message.contains("'labels' must be a mapping"),
            "{}",
            err.message
        );
        assert_eq!(err.at, Some((4, 9)), "{err:?}");
    }

    #[test]
    fn rejects_invalid_yaml_syntax_with_a_location() {
        let err = parse("title: [unterminated").unwrap_err();
        assert!(err.message.contains(':'), "{}", err.message);
        assert!(err.at.is_some(), "{err:?}");
    }

    #[test]
    fn plan_is_empty_when_nothing_changed() {
        let note = note(vec![label("todo", "")]);
        let meta = Metadata::from_note(&note);
        assert_eq!(plan(&note, &meta).unwrap(), vec![]);
    }

    #[test]
    fn plan_renames_when_the_title_changed() {
        let note = note(vec![]);
        let mut meta = Metadata::from_note(&note);
        meta.title = "New Title".into();
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Rename("New Title".into())]
        );
    }

    #[test]
    fn plan_adds_a_new_label() {
        let note = note(vec![]);
        let mut meta = Metadata::from_note(&note);
        meta.fields.push(Field {
            kind: Kind::Label,
            name: "todo".into(),
            value: "".into(),
            inheritable: false,
            at: None,
        });
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Set {
                attribute_id: None,
                kind: Kind::Label,
                name: "todo".into(),
                value: "".into(),
                inheritable: false,
            }]
        );
    }

    #[test]
    fn plan_removes_a_dropped_label() {
        let note = note(vec![label("todo", "")]);
        let mut meta = Metadata::from_note(&note);
        meta.fields.clear();
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Remove {
                attribute_id: "attr-todo-".into()
            }]
        );
    }

    #[test]
    fn plan_never_touches_a_system_relation() {
        let note = note(vec![relation("internalLink", "other1")]);
        let meta = Metadata::from_note(&note);
        assert_eq!(plan(&note, &meta).unwrap(), vec![]);
    }

    #[test]
    fn plan_rejects_a_changed_note_id() {
        let note = note(vec![]);
        let mut meta = Metadata::from_note(&note);
        meta.note_id = "different".into();
        assert!(plan(&note, &meta).is_err());
    }

    #[test]
    fn plan_rejects_a_changed_type() {
        let note = note(vec![]);
        let mut meta = Metadata::from_note(&note);
        meta.note_type = "code".into();
        assert!(plan(&note, &meta).is_err());
    }

    #[test]
    fn plan_updates_a_changed_value_in_place() {
        let note = note(vec![label("priority", "1")]);
        let mut meta = Metadata::from_note(&note);
        meta.fields[0].value = "2".into();
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Set {
                attribute_id: Some("attr-priority-1".into()),
                kind: Kind::Label,
                name: "priority".into(),
                value: "2".into(),
                inheritable: false,
            }]
        );
    }

    /// The bug a positional `find`-based diff had: two same-named instances
    /// both matching the same first existing attribute, so an added value
    /// silently overwrote the other instead of creating a second one.
    #[test]
    fn plan_adds_a_second_value_to_a_multivalued_label_without_touching_the_first() {
        let note = note(vec![label("genre", "sci-fi")]);
        let mut meta = Metadata::from_note(&note);
        meta.fields.push(Field {
            kind: Kind::Label,
            name: "genre".into(),
            value: "cyberpunk".into(),
            inheritable: false,
            at: None,
        });
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Set {
                attribute_id: None,
                kind: Kind::Label,
                name: "genre".into(),
                value: "cyberpunk".into(),
                inheritable: false,
            }]
        );
    }

    #[test]
    fn plan_removes_one_value_from_a_multivalued_label() {
        let note = note(vec![label("genre", "sci-fi"), label("genre", "cyberpunk")]);
        let mut meta = Metadata::from_note(&note);
        meta.fields.retain(|f| f.value != "cyberpunk");
        assert_eq!(
            plan(&note, &meta).unwrap(),
            vec![Change::Remove {
                attribute_id: "attr-genre-cyberpunk".into()
            }]
        );
    }
}
