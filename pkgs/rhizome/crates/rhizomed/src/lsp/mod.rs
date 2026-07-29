//! The Language Server Protocol surface, spoken over stdio.
//!
//! One process, one protocol. The note lifecycle -- fetching a note, writing it
//! back -- rides on custom `rhizome/*` requests rather than the standard
//! document methods, because `textDocument/didSave` is a notification and
//! cannot hand back the spliced HTML or a fresh `blobId`. Everything else is
//! ordinary LSP, which is what makes completion, hover and diagnostics work
//! without a line of bespoke Lua.
//!
//! The framing is hand-rolled. An off-the-shelf server crate would drag in an
//! async runtime, and the ETAPI client is deliberately blocking; JSON-RPC over
//! `Content-Length` is small enough that the trade is not worth making.

pub mod text;

use std::collections::{HashMap, HashSet};
use std::io::{BufRead, Write};

use anyhow::{Context, Result, anyhow, bail};
use rhizome_core::segment::{BlockKind, OpaqueReason, Resolved, Segments};
use rhizome_core::{buffer, segment, splice_resolved, verify_rebuild};
use rhizome_etapi::{Client, Note};
use serde_json::{Value, json};

use text::LineIndex;

use crate::index::{self, Child, Index, Listed};
use crate::meta;

const SEVERITY_ERROR: u8 = 1;
const SEVERITY_WARNING: u8 = 2;
const SEVERITY_HINT: u8 = 4;

/// How many times to re-read a note whose content changed while we were
/// fetching it.
const CONSISTENT_READ_ATTEMPTS: usize = 3;

/// Keywords `@` completion offers. Resolution (and day-note creation) happens
/// client-side, on accept -- see the `command` on each completion item.
const DATE_KEYWORDS: &[&str] = &["today", "yesterday", "tomorrow"];

pub fn serve(client: Client) -> Result<()> {
    let stdin = std::io::stdin();
    let mut reader = stdin.lock();
    let stdout = std::io::stdout();
    let mut writer = stdout.lock();

    let index = Index::new(index::cache_path(client.base_url()));
    spawn_index_refresh(client.clone(), index.clone());

    let mut server = Server::new(client, index);

    while let Some(message) = read_message(&mut reader)? {
        if server.handle(message, &mut writer)? {
            break;
        }
    }
    Ok(())
}

/// One-shot background fetch of the whole vault into `index`, notifying the
/// client when it lands (or fails) via `rhizome/indexStatus`. Runs once at
/// startup; `rhizome/reindex` repeats the same fetch synchronously, since an
/// explicit user action can afford to wait for it.
fn spawn_index_refresh(client: Client, index: Index) {
    std::thread::spawn(move || {
        let notification = index_status_notification(client.all_notes(), &index);
        // `Stdout::lock()` synchronizes with the main loop's own lock on the
        // same underlying handle (see the Rust stdlib docs for `Stdout`), so
        // this cannot interleave with, or race, a message the main thread is
        // writing at the same time.
        let stdout = std::io::stdout();
        let mut writer = stdout.lock();
        let _ = write_message(&mut writer, &notification);
    });
}

/// Applies a fetch result to `index` and builds the `rhizome/indexStatus`
/// notification describing it. Split out from `spawn_index_refresh` so the
/// "what happened" logic is testable without a background thread or a live
/// server.
fn index_status_notification(fetched: rhizome_etapi::Result<Vec<Note>>, index: &Index) -> Value {
    match fetched {
        Ok(notes) => {
            let count = notes.len();
            index.replace(notes);
            json!({
                "jsonrpc": "2.0",
                "method": "rhizome/indexStatus",
                "params": { "ok": true, "count": count },
            })
        }
        Err(err) => json!({
            "jsonrpc": "2.0",
            "method": "rhizome/indexStatus",
            "params": { "ok": false, "error": err.to_string(), "count": index.len() },
        }),
    }
}

struct Server {
    client: Client,
    documents: HashMap<String, Document>,
    /// Notes already given a forced revision this session.
    snapshotted: HashSet<String>,
    /// Note id to title, or `None` for "looked up and absent". Diagnostics
    /// would otherwise re-query the server for every link on every keystroke.
    titles: HashMap<String, Option<String>>,
    /// Rendered buffer text for notes that are not open as documents, keyed by
    /// note id and kept only while the `blobId` matches. Backlink and
    /// workspace-symbol lookups touch other notes on every use; without this
    /// each one would re-run the full fetch/segment/render pipeline.
    rendered: HashMap<String, (String, String)>,
    /// Every note's title and parents, for the path-aware note picker. Warm
    /// from disk on startup, refreshed in the background -- see `serve`.
    index: Index,
}

struct Document {
    note_id: String,
    title: String,
    blob_id: String,
    /// The buffer as the editor currently has it.
    text: String,
    body: Body,
}

/// How a note's content is carried in the buffer.
enum Body {
    /// A `text` note: CKEditor HTML, segmented and partly shown as Markdown.
    Text(Box<Segments>),
    /// A `code` note: already plain text, so no conversion happens at all.
    Code,
    /// Anything else. Shown so it can be read, never written.
    ReadOnly,
    /// The `trilium-meta://` pop-out: title, labels and relations as YAML.
    /// Writes go through `rhizome/applyMetadata`, its own request, not the
    /// generic `save` path (see `save`'s early exit below) -- there is no
    /// content to splice back into, only attribute calls to issue.
    Meta,
}

impl Server {
    fn new(client: Client, index: Index) -> Self {
        Self {
            client,
            documents: HashMap::new(),
            snapshotted: HashSet::new(),
            titles: HashMap::new(),
            rendered: HashMap::new(),
            index,
        }
    }

    /// Returns true once the client has asked the server to exit.
    fn handle(&mut self, message: Value, out: &mut impl Write) -> Result<bool> {
        let method = message["method"].as_str().unwrap_or_default().to_string();
        let params = message.get("params").cloned().unwrap_or(Value::Null);

        let Some(id) = message.get("id").cloned() else {
            match method.as_str() {
                "textDocument/didOpen" => self.did_open(&params, out)?,
                "textDocument/didChange" => self.did_change(&params, out)?,
                "textDocument/didClose" => {
                    if let Some(uri) = params["textDocument"]["uri"].as_str() {
                        self.documents.remove(&canonical_uri(uri));
                    }
                }
                "exit" => return Ok(true),
                _ => {}
            }
            return Ok(false);
        };

        let result = match method.as_str() {
            "initialize" => Ok(initialize_result()),
            "shutdown" => Ok(Value::Null),
            "rhizome/open" => self.open(&params),
            "rhizome/save" => self.save(&params, out),
            "rhizome/search" => self.search(&params),
            "rhizome/rename" => self.rename(&params),
            "rhizome/dateNote" => self.date_note(&params),
            "rhizome/inbox" => self.inbox(&params),
            "rhizome/create" => self.create(&params),
            "rhizome/clone" => self.clone_note(&params),
            "rhizome/move" => self.move_note(&params),
            "rhizome/unlink" => self.unlink_note(&params),
            "rhizome/delete" => self.delete_note(&params),
            "rhizome/archive" => self.archive_note(&params),
            "rhizome/unarchive" => self.unarchive_note(&params),
            "rhizome/titles" => self.batch_titles(&params),
            "rhizome/notes" => self.notes(&params),
            "rhizome/children" => self.children(&params),
            "rhizome/parents" => self.parents(&params),
            "rhizome/reindex" => self.reindex(),
            "rhizome/metadataDocument" => self.metadata_document(&params),
            "rhizome/metadataSchema" => self.metadata_schema(&params),
            "rhizome/applyMetadata" => self.apply_metadata(&params),
            "rhizome/dirty" => self.dirty(&params),
            "textDocument/completion" => self.completion(&params),
            "textDocument/hover" => self.hover(&params),
            "textDocument/definition" => self.definition(&params),
            "textDocument/inlayHint" => self.inlay_hint(&params),
            "textDocument/documentSymbol" => self.document_symbol(&params),
            "textDocument/references" => self.references(&params),
            "textDocument/documentLink" => self.document_link(&params),
            "workspace/symbol" => self.workspace_symbol(&params),
            "textDocument/foldingRange" => self.folding_range(&params),
            "textDocument/prepareRename" => self.prepare_rename(&params),
            "textDocument/rename" => self.rename_link(&params),
            "textDocument/codeAction" => self.code_action(&params),
            other => Err(anyhow!("unknown method '{other}'")),
        };

        let response = match result {
            Ok(value) => json!({ "jsonrpc": "2.0", "id": id, "result": value }),
            Err(error) => json!({
                "jsonrpc": "2.0",
                "id": id,
                "error": { "code": -32603, "message": format!("{error:#}") },
            }),
        };
        write_message(out, &response)?;
        Ok(false)
    }

    /// The `trilium://` URI to hand back as a definition/reference/link
    /// target for `note_id`, with a title suffix when one is known.
    ///
    /// The title matters for more than looks: the Lua plugin renames a
    /// note's buffer to `trilium://<id>/<title>` once it is open (`M.open`),
    /// and Neovim's built-in jump-to-location matches buffers by exact name.
    /// A target that only carried the bare id would create a second, empty
    /// buffer for a note already open under its titled name instead of
    /// jumping to it.
    fn link_uri(&self, note_id: &str) -> String {
        let title = self
            .index
            .get(note_id)
            .map(|e| e.title)
            .or_else(|| self.titles.get(note_id).cloned().flatten());
        match title {
            Some(title) if !title.is_empty() => {
                format!("trilium://{note_id}/{}", sanitize_title(&title))
            }
            _ => format!("trilium://{note_id}"),
        }
    }

    // Lifecycle

    /// Fetch a note and hand back the buffer text for it.
    fn open(&mut self, params: &Value) -> Result<Value> {
        let note_id = params["noteId"]
            .as_str()
            .context("open requires a noteId")?
            .to_string();

        let (note, content) = self.read_consistently(&note_id)?;
        if note.is_protected {
            bail!(
                "note '{note_id}' is protected; ETAPI cannot read it without an \
                 unlocked protected session"
            );
        }

        let (body, text) = match note.note_type.as_str() {
            "text" => {
                let segments = segment(&content);
                let text = buffer::render(&segments);
                (Body::Text(Box::new(segments)), text)
            }
            // Code notes are already plain text. Running them through
            // segmentation would be pure risk for no benefit.
            "code" => (Body::Code, content),
            _ => (Body::ReadOnly, content),
        };

        let uri = format!("trilium://{note_id}");
        let stats = match &body {
            Body::Text(segments) => {
                let s = segments.stats();
                json!({ "total": s.total, "transparent": s.transparent, "opaque": s.opaque() })
            }
            _ => Value::Null,
        };
        let read_only = matches!(body, Body::ReadOnly);

        self.titles
            .insert(note_id.clone(), Some(note.title.clone()));
        self.documents.insert(
            uri.clone(),
            Document {
                note_id: note_id.clone(),
                title: note.title.clone(),
                blob_id: note.blob_id.clone(),
                text: text.clone(),
                body,
            },
        );

        Ok(json!({
            "uri": uri,
            "noteId": note_id,
            "title": note.title,
            "blobId": note.blob_id,
            "buffer": text,
            "noteType": note.note_type,
            "mime": note.mime,
            "readOnly": read_only,
            "stats": stats,
        }))
    }

    /// Read a note's metadata and content as of a single revision.
    ///
    /// Metadata and content are two round trips, so a write landing between
    /// them yields a `blobId` that does not describe the content we hold.
    /// Re-reading until the id is stable either side of the content fetch keeps
    /// the staleness check on the save path honest.
    fn read_consistently(&self, note_id: &str) -> Result<(Note, String)> {
        let mut last = None;
        for _ in 0..CONSISTENT_READ_ATTEMPTS {
            let before = self.client.note(note_id).context("fetching note")?;
            let content = self.client.content(note_id).context("fetching content")?;
            let after = self.client.note(note_id).context("re-checking note")?;
            if before.blob_id == after.blob_id {
                return Ok((after, content));
            }
            last = Some((after, content));
        }
        // Somebody is writing continuously. Return the most recent read and let
        // the save-time check catch it.
        last.context("note kept changing while being read")
    }

    fn save(&mut self, params: &Value, out: &mut impl Write) -> Result<Value> {
        let uri = params["uri"].as_str().context("save requires a uri")?;
        let force = params["force"].as_bool().unwrap_or(false);

        let document = self.documents.get(uri).context("note is not open")?;
        if matches!(document.body, Body::ReadOnly) {
            bail!("'{}' notes are read-only in rhizome", document.note_id);
        }
        if matches!(document.body, Body::Meta) {
            bail!("metadata buffers are saved with rhizome/applyMetadata, not rhizome/save");
        }
        let note_id = document.note_id.clone();
        // The editor's copy is authoritative; `didChange` has already synced it.
        let text = match params["text"].as_str() {
            Some(text) => text.to_string(),
            None => document.text.clone(),
        };

        // ETAPI has no If-Match, so this is advisory and racy by construction:
        // the note can still change between here and the PUT below. It turns
        // silent clobbering into a prompt, which is the most the protocol allows.
        let current = self.client.note(&note_id)?;
        if current.blob_id != document.blob_id && !force {
            return Ok(json!({
                "conflict": true,
                "expectedBlobId": document.blob_id,
                "actualBlobId": current.blob_id,
            }));
        }

        let html = match &document.body {
            Body::Text(segments) => {
                let resolved = buffer::resolve(&text, segments);
                let rebuilt = splice_resolved(segments, &resolved);
                // Refuse rather than write something structurally broken; there
                // is no transaction to roll back and no If-Match to guard it.
                verify_rebuild(&rebuilt, segments)?;
                rebuilt
            }
            Body::Code => text.clone(),
            Body::ReadOnly => unreachable!("read-only rejected above"),
            Body::Meta => unreachable!("metadata buffers rejected above"),
        };

        // Snapshot before the first write of the session. Trilium's automatic
        // revisions are debounced by `revisionSnapshotTimeInterval` and may
        // decline to fire; this endpoint always creates one, so recovery does
        // not depend on rhizome being correct.
        if self.snapshotted.insert(note_id.clone()) {
            self.client
                .snapshot(&note_id, "before rhizome edit")
                .context("creating pre-edit revision")?;
        }

        self.client.set_content(&note_id, &html)?;
        self.rendered.remove(&note_id);

        // Re-read so the next save splices against what Trilium now holds.
        let (note, content) = self.read_consistently(&note_id)?;
        let (body, text) = match &self.documents[uri].body {
            Body::Text(_) => {
                let segments = segment(&content);
                let text = buffer::render(&segments);
                (Body::Text(Box::new(segments)), text)
            }
            Body::Code => (Body::Code, content),
            Body::ReadOnly => unreachable!(),
            Body::Meta => unreachable!(),
        };

        let document = self.documents.get_mut(uri).expect("checked above");
        document.blob_id = note.blob_id.clone();
        document.title = note.title.clone();
        document.text = text.clone();
        document.body = body;

        self.publish_diagnostics(uri, true, out)?;

        Ok(json!({
            "conflict": false,
            "blobId": note.blob_id,
            "buffer": text,
        }))
    }

    fn search(&mut self, params: &Value) -> Result<Value> {
        let query = params["query"].as_str().unwrap_or_default().trim();
        let limit = params["limit"].as_u64().unwrap_or(200) as u32;
        if query.is_empty() {
            // An empty query means "show me something useful", not "show me
            // the entire vault" -- recency is something only Trilium itself
            // knows (the local index tracks title/path, not dateModified),
            // so this one case stays a live call. `rhizome.pick("")` no
            // longer reaches this branch (see `rhizome/notes`), but the RPC
            // itself keeps the old behavior for any other caller.
            let notes = self.client.search(
                "note.type = text orderBy note.dateModified desc",
                Some(limit),
            )?;
            return Ok(Value::Array(
                notes.iter().map(note_summary).collect::<Vec<_>>(),
            ));
        }

        // The local index (title + ancestor path, the same word-prefix
        // matcher `[[` completion uses) answers instantly, with no round
        // trip. It only falls back to a live, content-scanning search
        // (Trilium's own `search`, not `fastSearch`) when it has nothing to
        // offer -- either because it hasn't finished its first load yet, or
        // because a genuine zero local matches means the query is more
        // likely raw Trilium search syntax (`#label=x`, a content phrase,
        // ...) than a note title or path.
        if !self.index.is_empty() {
            let listed = self.index.search(query, limit as usize);
            if !listed.is_empty() {
                return Ok(Value::Array(
                    listed.iter().map(listed_summary).collect::<Vec<_>>(),
                ));
            }
        }
        let notes = self.client.search(query, Some(limit))?;
        Ok(Value::Array(
            notes.iter().map(note_summary).collect::<Vec<_>>(),
        ))
    }

    // Metadata

    fn rename(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let title = params["title"]
            .as_str()
            .context("rename requires a title")?;
        let note = self.client.rename(&note_id, title)?;

        self.titles
            .insert(note_id.clone(), Some(note.title.clone()));
        self.index.upsert(&note);
        if let Some(document) = self.documents.get_mut(&format!("trilium://{note_id}")) {
            document.title = note.title.clone();
        }
        Ok(json!({ "noteId": note.note_id, "title": note.title }))
    }

    /// The metadata pop-out's text for a note. Registers the pop-out as an
    /// open document under `trilium-meta://<noteId>` so the usual `didOpen`
    /// sync, diagnostics, completion and hover all apply to it exactly like
    /// a `trilium://` buffer -- the Lua side attaches the LSP client to this
    /// uri once it names the buffer.
    fn metadata_document(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let note = self.client.note(&note_id)?;
        let text = meta::render(&meta::Metadata::from_note(&note));
        let uri = format!("trilium-meta://{note_id}");
        self.documents.insert(
            uri.clone(),
            Document {
                note_id: note_id.clone(),
                title: note.title.clone(),
                blob_id: note.blob_id.clone(),
                text: text.clone(),
                body: Body::Meta,
            },
        );
        Ok(json!({ "uri": uri, "noteId": note_id, "text": text }))
    }

    /// The label/relation definitions and vault-wide vocabulary in scope for
    /// a note, for `g?` help in the pop-out. Same data `metadata_completion`
    /// ranks from -- definitions first, each with its `promoted, single,
    /// type` detail, then every other vocabulary name -- just returned as a
    /// complete list instead of filtered against what's being typed.
    fn metadata_schema(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let definitions = self.index.definitions_for(&note_id);
        let vocabulary = self.index.vocabulary();
        Ok(json!({
            "labels": schema_section(meta::Kind::Label, &definitions, &vocabulary.label_names),
            "relations": schema_section(
                meta::Kind::Relation,
                &definitions,
                &vocabulary.relation_names,
            ),
        }))
    }

    /// Apply the pop-out's edited text: parse, diff against the live note,
    /// and issue only the ETAPI calls needed to close the gap.
    fn apply_metadata(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let text = params["text"].as_str().context("apply requires text")?;

        let desired = meta::parse(text).map_err(|e| anyhow!(e.message))?;
        let current = self.client.note(&note_id)?;
        let changes = meta::plan(&current, &desired).map_err(|e| anyhow!(e.message))?;

        let mut applied = 0usize;
        for change in &changes {
            match change {
                meta::Change::Rename(title) => {
                    let note = self.client.rename(&note_id, title)?;
                    self.titles.insert(note_id.clone(), Some(note.title));
                }
                meta::Change::Set {
                    attribute_id,
                    name,
                    value,
                    inheritable,
                    kind,
                } => {
                    let kind_str = match kind {
                        meta::Kind::Label => "label",
                        meta::Kind::Relation => "relation",
                    };
                    match attribute_id {
                        // ETAPI's PATCH /attributes/{id} can only change a
                        // label's `value` (and `position`, which this client
                        // does not track) -- never `isInheritable`, for
                        // either kind. An in-place value edit uses that PATCH
                        // and keeps the attribute's id and history; a change
                        // to `inheritable` has no in-place path at all and
                        // must delete-and-recreate, which loses only that one
                        // attribute's id rather than falling back to
                        // recreating everything the pop-out showed.
                        Some(id) => {
                            let existing =
                                current.attributes.iter().find(|a| a.attribute_id == *id);
                            let inheritable_changed = existing
                                .map(|a| a.is_inheritable != *inheritable)
                                .unwrap_or(false);
                            if inheritable_changed {
                                self.client.delete_attribute(id)?;
                                self.client.create_attribute(
                                    &note_id,
                                    kind_str,
                                    name,
                                    value,
                                    *inheritable,
                                )?;
                            } else {
                                self.client.update_attribute(id, value)?;
                            }
                        }
                        None => {
                            self.client.create_attribute(
                                &note_id,
                                kind_str,
                                name,
                                value,
                                *inheritable,
                            )?;
                        }
                    }
                }
                meta::Change::Remove { attribute_id } => {
                    self.client.delete_attribute(attribute_id)?;
                }
            }
            applied += 1;
        }

        let refreshed = self.client.note(&note_id)?;
        let refreshed_text = meta::render(&meta::Metadata::from_note(&refreshed));
        if let Some(document) = self.documents.get_mut(&format!("trilium-meta://{note_id}")) {
            document.text = refreshed_text.clone();
            document.title = refreshed.title.clone();
        }
        self.titles.insert(note_id.clone(), Some(refreshed.title));
        Ok(json!({ "applied": applied, "text": refreshed_text }))
    }

    /// Accept either a note id directly or the uri of an open buffer.
    fn note_id_of(&self, params: &Value) -> Result<String> {
        if let Some(note_id) = params["noteId"].as_str() {
            return Ok(note_id.to_string());
        }
        let uri = params["uri"]
            .as_str()
            .context("expected a noteId or the uri of an open note")?;
        let uri = canonical_uri(uri);
        self.documents
            .get(&uri)
            .map(|d| d.note_id.clone())
            .with_context(|| format!("'{uri}' is not open"))
    }

    // Navigation and creation

    /// Get-or-create the day note for `date` (`YYYY-MM-DD`, computed
    /// client-side so "today" means the editor's timezone, not the server's).
    fn date_note(&mut self, params: &Value) -> Result<Value> {
        let date = params["date"].as_str().context("date requires a date")?;
        let note = self.client.day_note(date)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    fn inbox(&mut self, params: &Value) -> Result<Value> {
        let date = params["date"].as_str().context("inbox requires a date")?;
        let note = self.client.inbox(date)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    fn create(&mut self, params: &Value) -> Result<Value> {
        let parent_note_id = params["parentNoteId"]
            .as_str()
            .context("create requires a parentNoteId")?;
        let title = params["title"]
            .as_str()
            .context("create requires a title")?;
        let note_type = params["type"].as_str().unwrap_or("text");
        let created = self
            .client
            .create_note(parent_note_id, title, note_type, "")?;
        self.index.upsert(&created.note);
        Ok(json!({ "noteId": created.note.note_id, "title": created.note.title }))
    }

    // Tree mutation

    /// Place `note_id` under `parentNoteId` as an additional branch. If one
    /// already exists there, ETAPI updates it in place rather than erroring,
    /// so this is naturally idempotent.
    fn clone_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let parent_note_id = params["parentNoteId"]
            .as_str()
            .context("clone requires a parentNoteId")?;
        self.client.create_branch(&note_id, parent_note_id)?;
        let note = self.client.note(&note_id)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    /// Move `note_id` from `fromParentNoteId` to `toParentNoteId`: create the
    /// new branch first, then delete the old one. That order matters -- if
    /// the delete step failed after an old-first ordering, the note would be
    /// left with no branch at all (Trilium deletes a note outright when its
    /// last branch goes); create-then-delete instead leaves a recoverable
    /// clone under both parents on any failure in between.
    fn move_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let from_parent_id = params["fromParentNoteId"]
            .as_str()
            .context("move requires a fromParentNoteId")?;
        let to_parent_id = params["toParentNoteId"]
            .as_str()
            .context("move requires a toParentNoteId")?;
        self.client.create_branch(&note_id, to_parent_id)?;
        self.delete_verified_branch(from_parent_id, &note_id)?;
        let note = self.client.note(&note_id)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    /// Remove `note_id` from `parentNoteId` without touching its other
    /// placements. Refuses when this is the note's only parent -- ETAPI
    /// would silently delete the note itself in that case, and unlinking is
    /// never the caller's intent when there is nothing else keeping the note
    /// alive; `rhizome/delete` is the explicit way to do that instead.
    fn unlink_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let parent_note_id = params["parentNoteId"]
            .as_str()
            .context("unlink requires a parentNoteId")?;
        let note = self.client.note(&note_id)?;
        if note.parent_note_ids.len() <= 1 {
            bail!(
                "'{}' has only one parent left -- unlinking would delete it; use delete instead",
                note.title
            );
        }
        self.delete_verified_branch(parent_note_id, &note_id)?;
        let note = self.client.note(&note_id)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    /// Delete `note_id` everywhere (every branch/clone at once). Soft on
    /// Trilium's side -- recoverable via `POST /notes/{id}/undelete` until
    /// erase runs, which is why this does not prompt.
    fn delete_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        self.client.delete_note(&note_id)?;
        self.index.remove(&note_id);
        self.documents.remove(&format!("trilium://{note_id}"));
        Ok(json!({ "noteId": note_id }))
    }

    /// Attach `#archived`, idempotently -- Trilium's own tree (and, once
    /// wired, `browse`) hides notes carrying it by default.
    fn archive_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let note = self.client.note(&note_id)?;
        if !note
            .attributes
            .iter()
            .any(|a| a.is_label() && a.name == "archived")
        {
            self.client
                .create_attribute(&note_id, "label", "archived", "", false)?;
        }
        let note = self.client.note(&note_id)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    /// Remove `#archived`, idempotently.
    fn unarchive_note(&mut self, params: &Value) -> Result<Value> {
        let note_id = self.note_id_of(params)?;
        let note = self.client.note(&note_id)?;
        if let Some(attribute) = note
            .attributes
            .iter()
            .find(|a| a.is_label() && a.name == "archived")
        {
            self.client.delete_attribute(&attribute.attribute_id)?;
        }
        let note = self.client.note(&note_id)?;
        self.index.upsert(&note);
        Ok(note_summary(&note))
    }

    /// Confirm a branch actually connects `parent_note_id` and `note_id`
    /// before deleting it -- `branch_id` is a derived, undocumented id
    /// (`${parentNoteId}_${noteId}`), so this turns that assumption into a
    /// checked precondition rather than a blind guess right before an
    /// irreversible call.
    fn delete_verified_branch(&self, parent_note_id: &str, note_id: &str) -> Result<()> {
        let branch_id = rhizome_etapi::branch_id(parent_note_id, note_id);
        let branch = self.client.get_branch(&branch_id)?;
        if branch.note_id != note_id || branch.parent_note_id != parent_note_id {
            bail!(
                "branch '{branch_id}' does not connect '{note_id}' and '{parent_note_id}' as expected -- refusing to delete it"
            );
        }
        self.client.delete_branch(&branch_id)?;
        Ok(())
    }

    // Document sync

    fn did_open(&mut self, params: &Value, out: &mut impl Write) -> Result<()> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        if let Some(text) = params["textDocument"]["text"].as_str()
            && let Some(document) = self.documents.get_mut(&uri)
        {
            document.text = text.to_string();
        }
        self.publish_diagnostics(&uri, true, out)
    }

    fn did_change(&mut self, params: &Value, out: &mut impl Write) -> Result<()> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        // Full sync: the last change carries the whole document.
        if let Some(change) = params["contentChanges"].as_array().and_then(|c| c.last())
            && let Some(text) = change["text"].as_str()
            && let Some(document) = self.documents.get_mut(&uri)
        {
            document.text = text.to_string();
        }
        // Link resolution is skipped here: it costs a round trip per unseen
        // note and this runs on every keystroke.
        self.publish_diagnostics(&uri, false, out)
    }

    // Diagnostics

    fn publish_diagnostics(
        &mut self,
        uri: &str,
        check_links: bool,
        out: &mut impl Write,
    ) -> Result<()> {
        if !self.documents.contains_key(uri) {
            return Ok(());
        }
        let diagnostics = self.diagnostics(uri, check_links);
        write_message(
            out,
            &json!({
                "jsonrpc": "2.0",
                "method": "textDocument/publishDiagnostics",
                "params": { "uri": uri, "diagnostics": diagnostics },
            }),
        )
    }

    fn diagnostics(&mut self, uri: &str, check_links: bool) -> Vec<Value> {
        let document = &self.documents[uri];
        let text = document.text.clone();
        let note_id = document.note_id.clone();
        let is_meta = matches!(document.body, Body::Meta);
        let index = LineIndex::new(&text);
        let mut out = Vec::new();

        if let Body::Text(segments) = &document.body {
            let resolved = buffer::resolve(&text, segments);
            let rebuilt = splice_resolved(segments, &resolved);
            if let Err(error) = verify_rebuild(&rebuilt, segments) {
                out.push(diagnostic(
                    (0, 0),
                    (0, 0),
                    SEVERITY_ERROR,
                    format!("{error} -- saving is blocked until this is fixed"),
                ));
            }
            out.extend(opaque_hints(&text, segments, &index));
            out.extend(task_list_degradation_hints(&text, segments, &index));
        }

        if check_links && let Body::Text(_) = &document.body {
            let links = text::wiki_links(&text);
            for link in links {
                if self.title_of(&link.note_id).is_none() {
                    out.push(diagnostic(
                        index.position(&text, link.start),
                        index.position(&text, link.end),
                        SEVERITY_WARNING,
                        format!("no note '{}' on this server", link.note_id),
                    ));
                }
            }
        }

        if is_meta {
            out.extend(self.metadata_diagnostics(&note_id, &text, check_links));
        }
        out
    }

    /// Diagnostics for the metadata pop-out: a parse failure (with the exact
    /// location `marked_yaml` reported) blocks everything else, since there
    /// is no reliable `Metadata` to check further. Once it parses, values are
    /// checked against any `label:`/`relation:` definition in scope; `Field`
    /// carries no position of its own, so those (and the relation-target
    /// check) land on the whole document rather than the specific line --
    /// the definition list at hover/completion time is where the precise
    /// spot to fix things comes from.
    fn metadata_diagnostics(&mut self, note_id: &str, text: &str, check_links: bool) -> Vec<Value> {
        let mut out = Vec::new();
        let desired = match meta::parse(text) {
            Ok(desired) => desired,
            Err(error) => {
                let start = match error.at {
                    Some((line, column)) => (
                        (line.saturating_sub(1)) as u32,
                        (column.saturating_sub(1)) as u32,
                    ),
                    None => (0, 0),
                };
                let end = (start.0, start.1 + 1);
                out.push(diagnostic(start, end, SEVERITY_ERROR, error.message));
                return out;
            }
        };

        let definitions = self.index.definitions_for(note_id);
        for ((kind, name), definition) in &definitions {
            let instances: Vec<&meta::Field> = desired
                .fields
                .iter()
                .filter(|f| f.kind == *kind && &f.name == name)
                .collect();
            if !definition.multi && instances.len() > 1 {
                // Anchored on the last instance -- the one most likely to
                // be the one the user just added, since `desired.fields`
                // preserves document order.
                let (start, end) = field_range(instances.last().unwrap());
                out.push(diagnostic(
                    start,
                    end,
                    SEVERITY_WARNING,
                    format!(
                        "'{name}' is defined as single-valued but has {} values",
                        instances.len()
                    ),
                ));
            }
            if let Some(label_type) = &definition.label_type {
                for field in &instances {
                    if !field.value.is_empty() && !value_matches_type(&field.value, label_type) {
                        let (start, end) = field_range(field);
                        out.push(diagnostic(
                            start,
                            end,
                            SEVERITY_WARNING,
                            format!(
                                "'{name}' is defined as {label_type}; '{}' does not look like one",
                                field.value
                            ),
                        ));
                    }
                }
            }
        }

        if check_links {
            for field in desired
                .fields
                .iter()
                .filter(|f| f.kind == meta::Kind::Relation)
            {
                if !field.value.is_empty() && self.title_of(&field.value).is_none() {
                    let (start, end) = field_range(field);
                    out.push(diagnostic(
                        start,
                        end,
                        SEVERITY_WARNING,
                        format!("no note '{}' on this server", field.value),
                    ));
                }
            }
        }

        out
    }

    /// Title of a note, or `None` if it does not exist. Cached both ways.
    fn title_of(&mut self, note_id: &str) -> Option<String> {
        if let Some(cached) = self.titles.get(note_id) {
            return cached.clone();
        }
        // The note index already has every title in memory; consulting it
        // saves a round trip for the common case (link titles, hover) where
        // the note hasn't been individually looked up this session but was
        // covered by the last bulk index fetch.
        if let Some(entry) = self.index.get(note_id) {
            self.titles
                .insert(note_id.to_string(), Some(entry.title.clone()));
            return Some(entry.title);
        }
        let found = self.client.note(note_id).ok().map(|n| n.title);
        self.titles.insert(note_id.to_string(), found.clone());
        found
    }

    /// A short preview of a linked note's content, for hover. `None` for
    /// note types where "content" is not meaningful prose (images, files,
    /// search notes, ...), and on any fetch error -- hover degrades to just
    /// the title rather than surfacing a failure the user did not ask for.
    fn hover_preview(&mut self, note_id: &str) -> Option<String> {
        let note_type = self.client.note(note_id).ok()?.note_type;
        if !matches!(note_type.as_str(), "text" | "code") {
            return None;
        }
        truncate_preview(&self.rendered(note_id).ok()?, HOVER_PREVIEW_LINES)
    }

    /// Live titles for a batch of note ids, for rendering `[[id|...]]` links
    /// as their current title rather than whatever text is frozen in the
    /// link -- Trilium itself treats that stored text as disposable, always
    /// overwriting it with the live title when it renders a reference link.
    fn batch_titles(&mut self, params: &Value) -> Result<Value> {
        let ids = params["noteIds"]
            .as_array()
            .context("titles requires noteIds")?;
        let mut out = serde_json::Map::new();
        for id in ids {
            let Some(id) = id.as_str() else { continue };
            out.insert(
                id.to_string(),
                match self.title_of(id) {
                    Some(title) => Value::String(title),
                    None => Value::Null,
                },
            );
        }
        Ok(Value::Object(out))
    }

    /// The whole local index, each note with its resolved ancestor path, for
    /// a path-aware picker. If the background fetch from `serve` hasn't
    /// landed yet and there was no disk cache to warm from, this blocks on
    /// one synchronous fetch rather than handing back an empty list -- a
    /// picker with nothing in it on a note's very first run is a worse
    /// experience than one extra round trip.
    fn notes(&mut self, _params: &Value) -> Result<Value> {
        if self.index.is_empty() {
            self.index.replace(self.client.all_notes()?);
        }
        let items: Vec<Value> = self
            .index
            .list()
            .into_iter()
            .map(|listed| {
                json!({
                    "noteId": listed.note_id,
                    "title": listed.title,
                    "path": listed.path,
                })
            })
            .collect();
        Ok(Value::Array(items))
    }

    /// The direct children of one note (its own title plus everything under
    /// it), for a drill-down picker to walk the tree one level at a time
    /// rather than filtering the flat `notes` list client-side. Same
    /// first-run fallback as `notes`.
    fn children(&mut self, params: &Value) -> Result<Value> {
        if self.index.is_empty() {
            self.index.replace(self.client.all_notes()?);
        }
        let note_id = self.note_id_of(params)?;
        let items: Vec<Value> = self
            .index
            .children(&note_id)
            .into_iter()
            .map(|child| child_summary(&child))
            .collect();
        let title = self.index.get(&note_id).map(|entry| entry.title);
        let trail: Vec<Value> = self
            .index
            .trail(&note_id)
            .into_iter()
            .map(|(id, title)| trail_summary(&id, &title))
            .collect();
        Ok(json!({ "noteId": note_id, "title": title, "trail": trail, "children": items }))
    }

    /// `note_id`'s own immediate parents -- for a buffer-bound move/unlink
    /// command, which (unlike `browse`) has no drill-down stack to read "the
    /// parent" off of and must ask instead, when there is more than one.
    fn parents(&mut self, params: &Value) -> Result<Value> {
        if self.index.is_empty() {
            self.index.replace(self.client.all_notes()?);
        }
        let note_id = self.note_id_of(params)?;
        let items: Vec<Value> = self
            .index
            .parents(&note_id)
            .into_iter()
            .map(|(id, title)| trail_summary(&id, &title))
            .collect();
        Ok(json!({ "parents": items }))
    }

    /// Force a full re-fetch of the index, blocking until it lands -- unlike
    /// the startup refresh, this is a deliberate user action (`:Rhizome
    /// reindex`), so waiting for it is expected rather than surprising.
    fn reindex(&mut self) -> Result<Value> {
        let notes = self.client.all_notes()?;
        let count = notes.len();
        self.index.replace(notes);
        Ok(json!({ "count": count }))
    }

    /// Buffer text for `note_id` as `buffer::render` would produce it,
    /// whether or not it is open. An open document's own copy (which may hold
    /// unsaved edits) always wins; otherwise this fetches and renders fresh,
    /// then caches by `blobId` for reuse by later lookups against the same
    /// note.
    fn rendered(&mut self, note_id: &str) -> Result<String> {
        let uri = format!("trilium://{note_id}");
        if let Some(document) = self.documents.get(&uri) {
            return Ok(document.text.clone());
        }
        let note = self.client.note(note_id)?;
        if let Some((blob_id, text)) = self.rendered.get(note_id)
            && *blob_id == note.blob_id
        {
            return Ok(text.clone());
        }
        let content = self.client.content(note_id)?;
        let text = match note.note_type.as_str() {
            "text" => buffer::render(&segment(&content)),
            _ => content,
        };
        self.rendered
            .insert(note_id.to_string(), (note.blob_id, text.clone()));
        Ok(text)
    }

    /// Byte ranges of buffer text not yet reflected in the note as last
    /// saved, translated to line ranges for a gutter marker. Backed by
    /// [`buffer::resolve_spans`], the same matcher the save path itself uses,
    /// so "dirty" here means exactly what `rhizome/save` would actually
    /// write.
    fn dirty(&mut self, params: &Value) -> Result<Value> {
        let uri = params["uri"].as_str().context("dirty requires a uri")?;
        let Some(document) = self.documents.get(uri) else {
            return Ok(json!({ "lines": [] }));
        };
        let Body::Text(segments) = &document.body else {
            return Ok(json!({ "lines": [] }));
        };
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let lines: Vec<Value> = buffer::resolve_spans(&text, segments)
            .into_iter()
            .filter(|(resolved, _)| !matches!(resolved, Resolved::Original(_)))
            .map(|(_, span)| {
                let start = index.position(&text, span.start).0;
                let end = index.position(&text, span.end.max(span.start)).0;
                json!({ "start": start, "end": end })
            })
            .collect();
        Ok(json!({ "lines": lines }))
    }

    // Language features

    fn completion(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(json!({ "isIncomplete": false, "items": [] }));
        };
        if matches!(document.body, Body::Meta) {
            return self.metadata_completion(&uri, params);
        }
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );

        if let Some((open, typed)) = text::at_prefix(&text, offset) {
            let start = index.position(&text, open);
            let end = index.position(&text, offset);
            let items: Vec<Value> = DATE_KEYWORDS
                .iter()
                .filter(|k| k.starts_with(typed))
                .map(|keyword| {
                    json!({
                        "label": format!("@{keyword}"),
                        "kind": 15,
                        "detail": "Trilium date note",
                        // The edit only removes the typed text; the client-side
                        // `command` (registered in Lua, run after the edit
                        // lands) does the actual lookup-or-create and inserts
                        // the real link. Nothing is created just by browsing
                        // the completion menu -- the calendar endpoint creates
                        // the day note as a side effect, so that has to wait
                        // until the item is actually chosen.
                        "textEdit": {
                            "range": range(start, end),
                            "newText": "",
                        },
                        "command": {
                            "title": "insert date note link",
                            "command": "rhizome.dateLink",
                            "arguments": [{ "keyword": keyword }],
                        },
                    })
                })
                .collect();
            return Ok(json!({ "isIncomplete": false, "items": items }));
        }

        let Some((open, typed)) = text::completion_prefix(&text, offset) else {
            return Ok(json!({ "isIncomplete": false, "items": [] }));
        };
        if typed.is_empty() {
            // Every note in the vault is not a useful completion list.
            return Ok(json!({ "isIncomplete": true, "items": [] }));
        }

        // The local index is a full-vault path+title search that returns
        // instantly (no round trip) and matches path components blink.cmp
        // would otherwise never see (see the `filterText` comment below). It
        // only falls back to the network when the index has not finished its
        // first load yet, so completion still works during that window --
        // just without path awareness until the background fetch lands.
        let notes: Vec<Listed> = if self.index.is_empty() {
            self.client
                .search_notes(&fulltext_query(typed), Some(50))
                .unwrap_or_default()
                .into_iter()
                .map(|note| Listed {
                    note_id: note.note_id,
                    title: note.title,
                    path: Vec::new(),
                })
                .collect()
        } else {
            self.index.search(typed, 50)
        };

        let start = index.position(&text, open);
        let end = index.position(&text, offset);
        let mut items: Vec<Value> = notes
            .iter()
            .enumerate()
            .map(|(rank, note)| {
                let breadcrumb = note.path.join(" > ");
                // blink.cmp fuzzy-matches (and filters!) against `filterText`
                // rather than `label`, using its own matcher rather than
                // `index::search` -- see `slug_path` for why this is the
                // shape that lets it. `sortText` carries the server's own
                // ranking through as a tiebreak once blink's own score is
                // equal.
                let mut item = json!({
                    "label": note.title,
                    "kind": 17,
                    "detail": note.note_id,
                    "filterText": slug_path(&note.path, &note.title),
                    "sortText": format!("{rank:04}"),
                    "textEdit": {
                        "range": range(start, end),
                        "newText": format!("[[{}|{}]]", note.note_id, note.title),
                    },
                });
                if !breadcrumb.is_empty() {
                    item["labelDetails"] = json!({ "description": breadcrumb });
                }
                item
            })
            .collect();

        // The index search above is still a single token: blink.cmp closes
        // its own completion popup the instant a space is typed, so a
        // multi-token query ("work proj alpha") can only be entered in a
        // picker, never inline here. The textEdit removes the whole
        // `[[typed` prefix (not just `typed`, unlike the `@today` items
        // above) so the client-side command can insert a complete
        // `[[id|title]]` regardless of how it was reached.
        items.push(json!({
            "label": "Search all notes...",
            "kind": 14,
            "detail": "path and title search across the whole vault",
            "textEdit": {
                "range": range(start, end),
                "newText": "",
            },
            "command": {
                "title": "search all notes",
                "command": "rhizome.searchNotes",
            },
        }));
        Ok(json!({ "isIncomplete": true, "items": items }))
    }

    /// Completion for the metadata pop-out: a name under `labels:`/
    /// `relations:` (from any `label:`/`relation:` definition in scope, then
    /// every name seen anywhere in the vault), or a value for the name under
    /// the cursor -- observed values for a label, or for a relation, a note
    /// search once something is typed and (nothing typed yet) notes already
    /// used for that same relation name elsewhere in the vault.
    fn metadata_completion(&mut self, uri: &str, params: &Value) -> Result<Value> {
        let document = &self.documents[uri];
        let text = document.text.clone();
        let note_id = document.note_id.clone();
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );

        let Some(context) = text::meta_context(&text, offset) else {
            return Ok(json!({ "isIncomplete": false, "items": [] }));
        };

        match context {
            text::MetaContext::Name {
                kind,
                typed,
                start,
                end,
            } => {
                let range = range(index.position(&text, start), index.position(&text, end));
                let definitions = self.index.definitions_for(&note_id);
                let vocabulary = self.index.vocabulary();
                let mut seen = HashSet::new();
                let mut items = Vec::new();
                for ((def_kind, name), definition) in &definitions {
                    if *def_kind != kind || !name.starts_with(&*typed) {
                        continue;
                    }
                    seen.insert(name.clone());
                    items.push(json!({
                        "label": name,
                        "kind": 5,
                        "detail": definition_detail(definition),
                        "sortText": format!("0{name}"),
                        "textEdit": { "range": range, "newText": format!("{name}:") },
                    }));
                }
                let vocabulary_names = match kind {
                    meta::Kind::Label => &vocabulary.label_names,
                    meta::Kind::Relation => &vocabulary.relation_names,
                };
                for name in vocabulary_names {
                    if seen.contains(name) || !name.starts_with(&*typed) {
                        continue;
                    }
                    items.push(json!({
                        "label": name,
                        "kind": 5,
                        "sortText": format!("1{name}"),
                        "textEdit": { "range": range, "newText": format!("{name}:") },
                    }));
                }
                Ok(json!({ "isIncomplete": true, "items": items }))
            }
            text::MetaContext::Value {
                kind,
                name,
                typed,
                start,
                end,
            } => {
                let range = range(index.position(&text, start), index.position(&text, end));
                if kind == meta::Kind::Relation {
                    let notes: Vec<Listed> = if typed.is_empty() {
                        // Nothing typed yet: suggest notes already used as
                        // a `name` target elsewhere in the vault, rather
                        // than nothing at all -- for `isFriendOf`, your
                        // existing friends.
                        let vocabulary = self.index.vocabulary();
                        let mut notes: Vec<Listed> = vocabulary
                            .values
                            .get(&(kind, name.clone()))
                            .into_iter()
                            .flatten()
                            .filter_map(|id| self.index.listed(id))
                            .collect();
                        notes.sort_by(|a, b| a.title.cmp(&b.title));
                        notes.truncate(20);
                        notes
                    } else {
                        self.index.search(&typed, 20)
                    };
                    let items: Vec<Value> = notes
                        .iter()
                        .enumerate()
                        .map(|(rank, note)| {
                            json!({
                                "label": note.title,
                                "kind": 17,
                                "detail": note.note_id,
                                "filterText": slug_path(&note.path, &note.title),
                                "sortText": format!("{rank:04}"),
                                "textEdit": { "range": range, "newText": note.note_id },
                            })
                        })
                        .collect();
                    return Ok(json!({ "isIncomplete": true, "items": items }));
                }
                let vocabulary = self.index.vocabulary();
                let mut values = vocabulary
                    .values
                    .get(&(kind, name))
                    .cloned()
                    .unwrap_or_default();
                values.sort();
                values.dedup();
                let items: Vec<Value> = values
                    .iter()
                    .filter(|v| v.starts_with(&*typed))
                    .map(|v| {
                        json!({
                            "label": v,
                            "kind": 12,
                            "textEdit": { "range": range, "newText": v },
                        })
                    })
                    .collect();
                Ok(json!({ "isIncomplete": true, "items": items }))
            }
        }
    }

    fn hover(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Null);
        };
        let text = document.text.clone();
        let note_id = document.note_id.clone();
        let is_meta = matches!(document.body, Body::Meta);
        let index = LineIndex::new(&text);
        let line = params["position"]["line"].as_u64().unwrap_or(0) as u32;
        let offset = index.offset(
            &text,
            line,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );

        if is_meta {
            return self.metadata_hover(&note_id, &text, offset);
        }

        if let Some(link) = text::link_at(&text, offset) {
            let body = match self.title_of(&link.note_id) {
                Some(title) => {
                    let mut body = format!("**{title}**\n\n`{}`", link.note_id);
                    if link.path != link.note_id {
                        body.push_str(&format!("\n\nlinked via `{}`", link.path));
                    }
                    if let Some(preview) = self.hover_preview(&link.note_id) {
                        body.push_str("\n\n---\n\n");
                        body.push_str(&preview);
                    }
                    body
                }
                None => format!(
                    "**missing note**\n\n`{}` is not on this server",
                    link.note_id
                ),
            };
            return Ok(json!({ "contents": { "kind": "markdown", "value": body } }));
        }

        // Hovering an opaque fence should say why it is raw HTML rather than
        // prose, since that is the question it provokes.
        if let Body::Text(segments) = &document.body
            && let Some(reason) = fence_reason_at_line(&text, segments, line)
        {
            return Ok(json!({
                "contents": {
                    "kind": "markdown",
                    "value": format!("**raw HTML block**\n\n{reason}"),
                }
            }));
        }
        Ok(Value::Null)
    }

    /// Hover for the metadata pop-out: a relation's value hovers like a
    /// `[[` link (title plus preview, or "missing note"); a name, in either
    /// section, hovers as its `label:`/`relation:` definition when one is in
    /// scope.
    fn metadata_hover(&mut self, note_id: &str, text: &str, offset: usize) -> Result<Value> {
        let Some(token) = text::meta_token_at(text, offset) else {
            return Ok(Value::Null);
        };

        if let text::MetaToken::Value {
            kind: meta::Kind::Relation,
            value,
            ..
        } = &token
            && !value.is_empty()
        {
            let body = match self.title_of(value) {
                Some(title) => {
                    let mut body = format!("**{title}**\n\n`{value}`");
                    if let Some(preview) = self.hover_preview(value) {
                        body.push_str("\n\n---\n\n");
                        body.push_str(&preview);
                    }
                    body
                }
                None => format!("**missing note**\n\n`{value}` is not on this server"),
            };
            return Ok(json!({ "contents": { "kind": "markdown", "value": body } }));
        }

        let (kind, name) = match token {
            text::MetaToken::Name { kind, name } => (kind, name),
            text::MetaToken::Value { kind, name, .. } => (kind, name),
        };
        let definitions = self.index.definitions_for(note_id);
        let Some(definition) = definitions.get(&(kind, name.clone())) else {
            return Ok(Value::Null);
        };
        Ok(json!({
            "contents": {
                "kind": "markdown",
                "value": format!("**{name}**\n\n{}", definition_detail(definition)),
            }
        }))
    }

    /// A title after every resolvable relation value, so `oGQC52TJQauf` and
    /// `andre` read as `Andre Selby` and `missing note` without changing
    /// what is actually in the buffer. Only fires in the metadata pop-out;
    /// the note body already carries live titles client-side, over its own
    /// `[[id|title]]` syntax (see `rhizome.links`), which this format has
    /// no equivalent of -- a bare id is all a relation value ever is.
    fn inlay_hint(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(json!([]));
        };
        if !matches!(document.body, Body::Meta) {
            return Ok(json!([]));
        }
        let text = document.text.clone();
        let Ok(desired) = meta::parse(&text) else {
            return Ok(json!([]));
        };
        let mut titles: HashMap<String, Option<String>> = HashMap::new();
        for field in desired
            .fields
            .iter()
            .filter(|f| f.kind == meta::Kind::Relation && !f.value.is_empty())
        {
            titles
                .entry(field.value.clone())
                .or_insert_with(|| self.title_of(&field.value));
        }
        Ok(json!(relation_hints(&text, &titles)))
    }

    fn definition(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Null);
        };
        let text = document.text.clone();
        let is_meta = matches!(document.body, Body::Meta);
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );

        if is_meta {
            return self.metadata_definition(&text, offset);
        }

        let Some(link) = text::link_at(&text, offset) else {
            return Ok(Value::Null);
        };
        Ok(json!({
            "uri": self.link_uri(&link.note_id),
            "range": range((0, 0), (0, 0)),
        }))
    }

    /// Goto-definition in the metadata pop-out: a relation's value is a note
    /// id, so it resolves exactly like a `[[...]]` link. A label's value is
    /// just a string, and a name (of either kind) is not a note reference at
    /// all -- hover, not definition, is where those show their meaning.
    fn metadata_definition(&mut self, text: &str, offset: usize) -> Result<Value> {
        let Some(text::MetaToken::Value {
            kind: meta::Kind::Relation,
            value,
            ..
        }) = text::meta_token_at(text, offset)
        else {
            return Ok(Value::Null);
        };
        if value.is_empty() || self.title_of(&value).is_none() {
            return Ok(Value::Null);
        }
        Ok(json!({
            "uri": self.link_uri(&value),
            "range": range((0, 0), (0, 0)),
        }))
    }

    fn document_symbol(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Array(Vec::new()));
        };
        let mut symbols = Vec::new();
        for (number, line) in document.text.lines().enumerate() {
            let number = number as u32;
            let (name, kind) = if let Some(rest) = line.strip_prefix('#') {
                let level = 1 + rest.chars().take_while(|c| *c == '#').count();
                (
                    format!(
                        "{} {}",
                        "#".repeat(level),
                        rest.trim_start_matches('#').trim()
                    ),
                    15,
                )
            } else if html_fence_id(line).is_some() {
                ("raw HTML block".to_string(), 26)
            } else {
                continue;
            };
            let span = range((number, 0), (number, line.chars().count() as u32));
            symbols.push(json!({
                "name": name,
                "kind": kind,
                "range": span,
                "selectionRange": span,
            }));
        }
        Ok(Value::Array(symbols))
    }

    /// Every note that links to the note under the cursor (or, off a link, to
    /// the document's own note). Backed by Trilium's own `~internalLink`
    /// relation, which the server maintains automatically on every content
    /// write -- an exact index, not a text search.
    fn references(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Array(Vec::new()));
        };
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );
        let target = match text::link_at(&text, offset) {
            Some(link) => link.note_id,
            None => document.note_id.clone(),
        };

        let query = format!("~internalLink.noteId = \"{}\"", target.replace('"', ""));
        let notes = self.client.search(&query, Some(200)).unwrap_or_default();

        let mut locations = Vec::new();
        for note in notes {
            let Ok(rendered) = self.rendered(&note.note_id) else {
                continue;
            };
            let rendered_index = LineIndex::new(&rendered);
            for link in text::wiki_links(&rendered) {
                if link.note_id == target {
                    locations.push(json!({
                        "uri": self.link_uri(&note.note_id),
                        "range": range(
                            rendered_index.position(&rendered, link.start),
                            rendered_index.position(&rendered, link.end),
                        ),
                    }));
                }
            }
        }
        Ok(Value::Array(locations))
    }

    /// Every `[[...]]` in the buffer as a clickable range, so `<C-]>`-style
    /// jump-to-target UIs and gutter link markers work without a manual scan.
    fn document_link(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Array(Vec::new()));
        };
        let text = &document.text;
        let index = LineIndex::new(text);
        let links: Vec<Value> = text::wiki_links(text)
            .into_iter()
            .map(|link| {
                json!({
                    "range": range(index.position(text, link.start), index.position(text, link.end)),
                    "target": self.link_uri(&link.note_id),
                })
            })
            .collect();
        Ok(Value::Array(links))
    }

    /// `workspace/symbol` over the same search Trilium's picker uses, so any
    /// LSP-aware fuzzy finder can reach a note without going through
    /// `rhizome/search`.
    fn workspace_symbol(&mut self, params: &Value) -> Result<Value> {
        let query = params["query"].as_str().unwrap_or_default().trim();
        if query.is_empty() {
            return Ok(Value::Array(Vec::new()));
        }
        let notes = self
            .client
            .search_notes(&fulltext_query(query), Some(50))
            .unwrap_or_default();
        // `link_uri` reads the title cache rather than trusting a title
        // handed to it directly, since every other call site only has a
        // note id to work from. Here the search result already carries the
        // title, so warm the cache with it first rather than letting
        // `link_uri` fall back to a bare, unsuffixed URI for a note the
        // index or cache simply hasn't seen yet.
        for note in &notes {
            self.titles
                .insert(note.note_id.clone(), Some(note.title.clone()));
        }
        let symbols: Vec<Value> = notes
            .iter()
            .map(|note| {
                json!({
                    "name": note.title,
                    "kind": 17,
                    "location": {
                        "uri": self.link_uri(&note.note_id),
                        "range": range((0, 0), (0, 0)),
                    },
                })
            })
            .collect();
        Ok(Value::Array(symbols))
    }

    /// One fold per opaque `` `=html `` fence, matching the pairs of opener
    /// and closer lines `buffer::render` emits. Replaces the Lua `foldexpr`
    /// regex, which has to be kept in lockstep with the fence syntax by hand
    /// every time that syntax changes (as it just did for adaptive fence
    /// length) -- the server already knows exactly where every fence is.
    fn folding_range(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Array(Vec::new()));
        };
        let mut ranges = Vec::new();
        let mut open: Option<u32> = None;
        for (number, line) in document.text.lines().enumerate() {
            let number = number as u32;
            if html_fence_id(line).is_some() {
                open = Some(number);
            } else if open.is_some() && line.trim_start_matches('`').is_empty() && !line.is_empty()
            {
                ranges.push(json!({
                    "startLine": open.unwrap(),
                    "endLine": number,
                    "kind": "region",
                }));
                open = None;
            }
        }
        Ok(Value::Array(ranges))
    }

    /// Whether the cursor is on the raw-text form of a link the client can
    /// rename, and the range that form covers -- LSP requires a rename be
    /// offered only where one is actually possible.
    fn prepare_rename(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Null);
        };
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );
        let Some(link) = text::link_at(&text, offset) else {
            return Ok(Value::Null);
        };
        Ok(json!({
            "range": range(index.position(&text, link.start), index.position(&text, link.end)),
            "placeholder": link.title,
        }))
    }

    /// Rename the note a link under the cursor points to. This renames the
    /// note itself only -- the stored text inside other notes' `[[id|title]]`
    /// links is never rewritten, because Trilium's own renderer overwrites it
    /// unconditionally with the live title on display (`loadReferenceLinkTitle`
    /// in `link.ts`), so those copies are dead cache rhizome's link-titles
    /// overlay already ignores.
    fn rename_link(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let new_title = params["newName"]
            .as_str()
            .context("rename requires newName")?;
        let Some(document) = self.documents.get(&uri) else {
            bail!("note is not open");
        };
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let offset = index.offset(
            &text,
            params["position"]["line"].as_u64().unwrap_or(0) as u32,
            params["position"]["character"].as_u64().unwrap_or(0) as u32,
        );
        let Some(link) = text::link_at(&text, offset) else {
            bail!("no note reference at the cursor");
        };

        let note = self.client.rename(&link.note_id, new_title)?;
        self.titles
            .insert(link.note_id.clone(), Some(note.title.clone()));
        self.index.upsert(&note);
        if let Some(renamed) = self
            .documents
            .get_mut(&format!("trilium://{}", link.note_id))
        {
            renamed.title = note.title.clone();
        }
        // No text in any buffer needs editing -- the rename overlay reads the
        // title live on the next redraw. An empty edit set is a valid
        // WorkspaceEdit and tells the client the rename succeeded.
        Ok(json!({ "changes": {} }))
    }

    /// A broken link under the cursor offers "create this note"; a link
    /// written as a full notePath rather than a bare noteId offers
    /// "simplify link target", opt-in since the path is not actually wrong
    /// -- Trilium itself emits both forms. Inside the metadata pop-out, see
    /// `metadata_code_actions` instead.
    fn code_action(&mut self, params: &Value) -> Result<Value> {
        let uri = canonical_uri(params["textDocument"]["uri"].as_str().unwrap_or_default());
        let Some(document) = self.documents.get(&uri) else {
            return Ok(Value::Array(Vec::new()));
        };
        let text = document.text.clone();
        let index = LineIndex::new(&text);
        let range_start = index.offset(
            &text,
            params["range"]["start"]["line"].as_u64().unwrap_or(0) as u32,
            params["range"]["start"]["character"].as_u64().unwrap_or(0) as u32,
        );

        if matches!(document.body, Body::Meta) {
            return Ok(json!(self.metadata_code_actions(
                &text,
                range_start,
                &index
            )));
        }

        let Some(link) = text::link_at(&text, range_start) else {
            return Ok(Value::Array(Vec::new()));
        };
        // A missing note and a simplifiable path are mutually exclusive: the
        // former means the target (already resolved to its notePath tail)
        // does not exist; the latter only makes sense once it does.
        if self.title_of(&link.note_id).is_none() {
            return Ok(json!([{
                "title": format!("Create note '{}'", link.title),
                "command": {
                    "title": "create note",
                    "command": "rhizome.createFromLink",
                    // `link.path` -- not `link.note_id` -- since the client
                    // rewrites buffer text and must match what is actually
                    // there, which may be a full notePath.
                    "arguments": [{ "oldNoteId": link.path, "title": link.title }],
                },
            }]));
        }
        if link.path != link.note_id {
            return Ok(json!([{
                "title": "Simplify link target",
                "command": {
                    "title": "simplify link target",
                    "command": "rhizome.simplifyLink",
                    "arguments": [{ "path": link.path, "noteId": link.note_id }],
                },
            }]));
        }
        Ok(Value::Array(Vec::new()))
    }

    /// Code actions inside the metadata pop-out: "convert to list" on a
    /// bare `name: value` line, and "create note" on a relation value that
    /// does not resolve to one. Unlike the wikilink action above, a
    /// metadata value has no `[[...]]` delimiters to search-and-replace
    /// within, so both actions hand the client the exact line number and
    /// the parsed name/value rather than a text pattern -- the edit is
    /// applied against that specific line, not a buffer-wide substitution.
    fn metadata_code_actions(
        &mut self,
        text: &str,
        offset: usize,
        index: &LineIndex,
    ) -> Vec<Value> {
        let mut actions = Vec::new();
        let line = index.position(text, offset).0;

        if let Some(field) = text::convertible_value_at(text, offset) {
            actions.push(json!({
                "title": "Convert to list",
                "command": {
                    "title": "convert to list",
                    "command": "rhizome.convertToList",
                    "arguments": [{ "line": line, "name": field.name, "value": field.value }],
                },
            }));
        }

        if let Some(text::MetaToken::Value {
            kind: meta::Kind::Relation,
            value,
            ..
        }) = text::meta_token_at(text, offset)
            && !value.is_empty()
            && self.title_of(&value).is_none()
        {
            actions.push(json!({
                "title": format!("Create note '{value}'"),
                "command": {
                    "title": "create note",
                    "command": "rhizome.createFromMetadataValue",
                    "arguments": [{ "value": value, "line": line }],
                },
            }));
        }

        actions
    }
}

/// A safe fulltext query fragment for `typed`, for use with
/// `Client::search_notes`. Wrapping it in quotes takes Trilium's lexer out of
/// expression mode for the whole token (`lex.ts` only treats `#`, `~`, and
/// `note.` as syntax outside quotes), so a stray character in a note title
/// being searched for -- "C#", "note.js" -- can never be misparsed as an
/// attribute comparison. `fastSearch` (set by `search_notes`) then routes
/// this straight to `NoteFlatTextExp`, which is what gives fuzzy title
/// matching and matches against the note's ancestor path -- neither of which
/// the old `note.title *=* "..."` attribute comparison could do.
fn fulltext_query(typed: &str) -> String {
    format!("\"{}\"", typed.replace('"', ""))
}

/// Normalize a `trilium://` URI down to `trilium://<noteId>`.
///
/// The Lua plugin names buffers `trilium://<id>/<title>` purely so bufferline,
/// `:t`, and the tabline show something readable -- see `M.open` in
/// `lua/rhizome/init.lua`. Neovim's built-in LSP client derives every
/// `textDocument.uri` it sends from the buffer's *current* name, so that
/// title suffix reaches every standard request (`didChange`, `completion`,
/// `hover`, ...) verbatim. `self.documents` is keyed by noteId alone; this is
/// the single place that gap is closed, so a title (which can change, and is
/// not unique) never becomes part of a document's identity.
fn canonical_uri(raw: &str) -> String {
    match raw.strip_prefix("trilium://") {
        Some(rest) => format!("trilium://{}", rest.split('/').next().unwrap_or(rest)),
        None => raw.to_string(),
    }
}

/// ASCII substitute for characters that would either be eaten by `:t` (a
/// literal `/`) or corrupt the buffer name (control characters).
///
/// Kept in lockstep with `sanitize_title` in `lua/rhizome/init.lua`: the same
/// title has to sanitize to the same string on both sides, or a note opened
/// directly and the same note reached through a link end up as two different
/// buffer names for one note.
fn sanitize_title(title: &str) -> String {
    title
        .chars()
        .map(|c| {
            if matches!(c, '/' | '\n' | '\r' | '\t') {
                '-'
            } else {
                c
            }
        })
        .collect()
}

/// `path` and `title` reduced to a single lowercase, dash-separated slug --
/// `["Waystone", "People"], "Alice Smith"` -> `"waystone-people-alice-smith"`.
///
/// This is what a completion item's `filterText` is built from (see
/// `completion`): blink.cmp fuzzy-matches and ranks against `filterText`
/// rather than the label, using its own matcher, not this crate's
/// `index::search` -- so the two have to agree on what a query like
/// "waystonepeople" or "waystone-people" means. Measured directly against
/// blink's matcher, this shape (lowercase, `-`-joined, path first) beat
/// every other one tried (title-first, unseparated, slash-joined) on every
/// query shape tried, and is the only one that can match a full path at
/// all: a title-first ordering puts a path query out of order, and `-` is
/// one of the few punctuation characters blink's own keyword regex accepts
/// mid-word, so it never closes the completion menu the way a space would.
fn slug_path(path: &[String], title: &str) -> String {
    let mut words: Vec<String> = Vec::new();
    for segment in path
        .iter()
        .map(String::as_str)
        .chain(std::iter::once(title))
    {
        words.extend(
            segment
                .split(|c: char| !c.is_alphanumeric())
                .filter(|w| !w.is_empty())
                .map(|w| w.to_lowercase()),
        );
    }
    words.join("-")
}

/// Strip a variable-length backtick opener (`` `+=html <id> ``) down to the
/// id, matching whatever fence length `buffer::render` chose for this block.
fn html_fence_id(line: &str) -> Option<&str> {
    let rest = line.trim_start_matches('`');
    if rest.len() == line.len() {
        return None;
    }
    rest.strip_prefix("=html").map(str::trim)
}

fn note_summary(note: &Note) -> Value {
    json!({
        "noteId": note.note_id,
        "title": note.title,
        "noteType": note.note_type,
        "mime": note.mime,
    })
}

/// Same shape as `note_summary`, for a local-index match rather than a live
/// `Note` -- the index knows a note's ancestor path but not its type/mime, so
/// this carries `path` instead. The Lua client picks whichever fields are
/// present to decide how to display a result.
fn listed_summary(note: &Listed) -> Value {
    json!({
        "noteId": note.note_id,
        "title": note.title,
        "path": note.path,
    })
}

fn child_summary(child: &Child) -> Value {
    json!({
        "noteId": child.note_id,
        "title": child.title,
        "childCount": child.child_count,
        "cloneCount": child.clone_count,
        "archived": child.archived,
    })
}

/// One `rhizome/children` trail entry -- an ancestor's id paired with its
/// title, in root-to-leaf order. See `Index::trail`.
fn trail_summary(note_id: &str, title: &str) -> Value {
    json!({
        "noteId": note_id,
        "title": title,
    })
}

/// The inlay hints `inlay_hint` reports for `text`, given each relation
/// value's already-resolved title (or `None` for a value that resolved to
/// no note) -- kept apart from the lookup itself so the position math can
/// be tested without a `Server` to look titles up through.
fn relation_hints(text: &str, titles: &HashMap<String, Option<String>>) -> Vec<Value> {
    let Ok(desired) = meta::parse(text) else {
        return Vec::new();
    };
    let index = LineIndex::new(text);
    let mut hints = Vec::new();
    for field in desired
        .fields
        .iter()
        .filter(|f| f.kind == meta::Kind::Relation && !f.value.is_empty())
    {
        let Some((line, _)) = field.at else {
            continue;
        };
        let label = match titles.get(&field.value) {
            Some(Some(title)) => format!("  {title}"),
            _ => "  missing note".to_string(),
        };
        // End of the value's own line -- true for both a `name: id` and a
        // `- id` list entry -- found by asking for a character far past
        // any line's length, which `LineIndex::offset` clamps to the
        // newline (or the end of text, on the last line).
        let end_byte = index.offset(text, (line - 1) as u32, u32::MAX);
        let (hint_line, character) = index.position(text, end_byte);
        hints.push(json!({
            "position": { "line": hint_line, "character": character },
            "label": label,
            "paddingLeft": true,
        }));
    }
    hints
}

/// Mark every opaque block, so the buffer says plainly which parts are being
/// shown as raw HTML and why.
fn opaque_hints(text: &str, segments: &Segments, index: &LineIndex) -> Vec<Value> {
    let reasons: HashMap<&str, OpaqueReason> = segments
        .blocks()
        .filter_map(|block| match &block.kind {
            BlockKind::Opaque { reason } => Some((block.id.as_str(), *reason)),
            BlockKind::Transparent { .. } | BlockKind::Spacer => None,
        })
        .collect();

    let mut out = Vec::new();
    let mut offset = 0usize;
    for line in text.lines() {
        if let Some(id) = html_fence_id(line)
            && let Some(reason) = reasons.get(id)
        {
            let start = index.position(text, offset);
            let end = index.position(text, offset + line.len());
            out.push(diagnostic(start, end, SEVERITY_HINT, describe(*reason)));
        }
        offset += line.len() + 1;
    }
    out
}

/// Diagnostics for buffer spans where a fresh conversion had to degrade a
/// checkbox to literal `[ ]`/`[x]` text -- see `buffer::task_list_degradations`.
fn task_list_degradation_hints(text: &str, segments: &Segments, index: &LineIndex) -> Vec<Value> {
    buffer::task_list_degradations(text, segments)
        .into_iter()
        .map(|span| {
            diagnostic(
                index.position(text, span.start),
                index.position(text, span.end),
                SEVERITY_WARNING,
                "this checkbox has no CKEditor form here (mixed bullet/checkbox list, \
                 ordered task list, or an unrecognised shape) and will be saved as \
                 literal `[ ]`/`[x]` text instead of a checkbox"
                    .to_string(),
            )
        })
        .collect()
}

fn fence_reason_at_line(text: &str, segments: &Segments, line: u32) -> Option<String> {
    let target = text.lines().nth(line as usize)?;
    let id = html_fence_id(target)?;
    segments.blocks().find_map(|block| match &block.kind {
        BlockKind::Opaque { reason } if block.id == id => Some(describe(*reason)),
        _ => None,
    })
}

const HOVER_PREVIEW_LINES: usize = 15;

/// The first `max_lines` of `text`, with a trailing `...` if more was cut.
/// `None` if there was nothing to show (empty or all-whitespace).
fn truncate_preview(text: &str, max_lines: usize) -> Option<String> {
    let mut lines: Vec<&str> = text.lines().take(max_lines).collect();
    if text.lines().count() > max_lines {
        lines.push("...");
    }
    let preview = lines.join("\n");
    if preview.trim().is_empty() {
        None
    } else {
        Some(preview)
    }
}

fn describe(reason: OpaqueReason) -> String {
    match reason {
        OpaqueReason::NoRule => {
            "no Markdown form for this construct, so it is shown and saved as HTML".into()
        }
        OpaqueReason::VerificationFailed => {
            "converting this to Markdown and back did not reproduce it exactly, \
             so the original HTML is kept instead"
                .into()
        }
        OpaqueReason::Unparseable => {
            "this note could not be scanned into blocks, so it is held as one piece".into()
        }
        OpaqueReason::Ambiguous => {
            "this list sits directly next to another list of the same kind, and the two \
             cannot be told apart once rendered, so it is shown and saved as HTML"
                .into()
        }
    }
}

fn diagnostic(start: (u32, u32), end: (u32, u32), severity: u8, message: String) -> Value {
    json!({
        "range": range(start, end),
        "severity": severity,
        "source": "rhizome",
        "message": message,
    })
}

/// A one-character diagnostic range at `field`'s value, converting its
/// 1-based `(line, column)` to LSP's 0-based positions -- or the top of the
/// document if the field carries no position (only ever a `Field` built by
/// hand rather than parsed, which `metadata_diagnostics` never sees).
fn field_range(field: &meta::Field) -> ((u32, u32), (u32, u32)) {
    let start = match field.at {
        Some((line, column)) => (
            (line.saturating_sub(1)) as u32,
            (column.saturating_sub(1)) as u32,
        ),
        None => (0, 0),
    };
    (start, (start.0, start.1 + 1))
}

/// A conservative structural check against a Trilium promoted-label type.
/// Only `number` and `boolean` are validated -- unambiguous and cheap, and
/// exactly the two types a typo silently turns into a wrong-but-plausible
/// value. Date/time types are left alone rather than hand-rolling a fragile
/// format validator for what is only ever a soft warning.
fn value_matches_type(value: &str, label_type: &str) -> bool {
    match label_type {
        "number" => value.parse::<f64>().is_ok(),
        "boolean" => matches!(value, "true" | "false"),
        _ => true,
    }
}

/// A one-line summary of a `label:`/`relation:` definition, for a
/// completion item's `detail`.
fn definition_detail(definition: &index::Definition) -> String {
    let mut parts = Vec::new();
    if definition.promoted {
        parts.push("promoted".to_string());
    }
    parts.push(if definition.multi { "multi" } else { "single" }.to_string());
    if let Some(label_type) = &definition.label_type {
        parts.push(label_type.clone());
    }
    parts.join(", ")
}

/// One `labels`/`relations` entry for `metadata_schema`: every definition of
/// `kind`, alphabetical, then every other vocabulary name not already
/// covered by one, also alphabetical.
fn schema_section(
    kind: meta::Kind,
    definitions: &HashMap<(meta::Kind, String), index::Definition>,
    vocabulary_names: &[String],
) -> Value {
    let mut defined: Vec<(&String, &index::Definition)> = definitions
        .iter()
        .filter(|((k, _), _)| *k == kind)
        .map(|((_, name), definition)| (name, definition))
        .collect();
    defined.sort_by(|a, b| a.0.cmp(b.0));

    let mut items: Vec<Value> = defined
        .into_iter()
        .map(|(name, definition)| {
            json!({ "name": name, "detail": definition_detail(definition), "defined": true })
        })
        .collect();

    let mut other: Vec<&String> = vocabulary_names
        .iter()
        .filter(|name| !definitions.contains_key(&(kind, (*name).clone())))
        .collect();
    other.sort();
    items.extend(
        other
            .into_iter()
            .map(|name| json!({ "name": name, "detail": Value::Null, "defined": false })),
    );

    Value::Array(items)
}

fn range(start: (u32, u32), end: (u32, u32)) -> Value {
    json!({
        "start": { "line": start.0, "character": start.1 },
        "end": { "line": end.0, "character": end.1 },
    })
}

fn initialize_result() -> Value {
    json!({
        "capabilities": {
            "positionEncoding": "utf-16",
            // Full sync. Notes are small and the server re-segments anyway.
            "textDocumentSync": { "openClose": true, "change": 1 },
            "completionProvider": { "triggerCharacters": ["[", "@", ":", "-"] },
            "hoverProvider": true,
            "definitionProvider": true,
            "inlayHintProvider": true,
            "documentSymbolProvider": true,
            "referencesProvider": true,
            "documentLinkProvider": { "resolveProvider": false },
            "workspaceSymbolProvider": true,
            "foldingRangeProvider": true,
            "renameProvider": { "prepareProvider": true },
            "codeActionProvider": true,
        },
        "serverInfo": { "name": "rhizome", "version": env!("CARGO_PKG_VERSION") },
    })
}

fn read_message(reader: &mut impl BufRead) -> Result<Option<Value>> {
    let mut length: Option<usize> = None;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            return Ok(None);
        }
        let line = line.trim_end();
        if line.is_empty() {
            break;
        }
        if let Some(value) = line.strip_prefix("Content-Length:") {
            length = Some(value.trim().parse().context("bad Content-Length")?);
        }
    }
    let length = length.context("message header without Content-Length")?;
    let mut body = vec![0u8; length];
    std::io::Read::read_exact(reader, &mut body)?;
    Ok(Some(serde_json::from_slice(&body)?))
}

fn write_message(writer: &mut impl Write, message: &Value) -> Result<()> {
    let body = serde_json::to_vec(message)?;
    write!(writer, "Content-Length: {}\r\n\r\n", body.len())?;
    writer.write_all(&body)?;
    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_a_message_with_a_byte_length_header() {
        let mut out = Vec::new();
        write_message(&mut out, &json!({ "a": "é" })).unwrap();
        let text = String::from_utf8(out).unwrap();
        // `{"a":"é"}` is 9 characters but 10 bytes, and the header counts bytes.
        assert!(text.starts_with("Content-Length: 10\r\n\r\n"), "{text}");
    }

    #[test]
    fn reads_back_a_framed_message() {
        let mut out = Vec::new();
        write_message(&mut out, &json!({ "method": "initialize" })).unwrap();
        let mut cursor = std::io::Cursor::new(out);
        let message = read_message(&mut cursor).unwrap().unwrap();
        assert_eq!(message["method"], "initialize");
        assert!(read_message(&mut cursor).unwrap().is_none());
    }

    #[test]
    fn advertises_the_capabilities_the_client_relies_on() {
        let capabilities = initialize_result();
        let capabilities = &capabilities["capabilities"];
        assert_eq!(capabilities["hoverProvider"], true);
        assert_eq!(capabilities["definitionProvider"], true);
        assert_eq!(
            capabilities["completionProvider"]["triggerCharacters"][0],
            "["
        );
    }

    #[test]
    fn listed_summary_carries_path_instead_of_note_type() {
        let listed = Listed {
            note_id: "abc123".to_string(),
            title: "Alice Smith".to_string(),
            path: vec!["Waystone".to_string(), "People".to_string()],
        };
        let summary = listed_summary(&listed);
        assert_eq!(summary["noteId"], "abc123");
        assert_eq!(summary["title"], "Alice Smith");
        assert_eq!(summary["path"][0], "Waystone");
        assert_eq!(summary["path"][1], "People");
        assert!(summary.get("noteType").is_none());
    }

    #[test]
    fn child_summary_carries_child_and_clone_counts() {
        let child = Child {
            note_id: "abc123".to_string(),
            title: "Alice Smith".to_string(),
            child_count: 3,
            clone_count: 1,
            archived: false,
        };
        let summary = child_summary(&child);
        assert_eq!(summary["noteId"], "abc123");
        assert_eq!(summary["title"], "Alice Smith");
        assert_eq!(summary["childCount"], 3);
        assert_eq!(summary["cloneCount"], 1);
        assert_eq!(summary["archived"], false);
    }

    #[test]
    fn trail_summary_pairs_an_ancestors_id_with_its_title() {
        let summary = trail_summary("work", "Work");
        assert_eq!(summary["noteId"], "work");
        assert_eq!(summary["title"], "Work");
    }

    #[test]
    fn opaque_blocks_are_reported_where_their_fence_is() {
        let html = r#"<p>fine</p>
<figure class="image"><img src="a.png" width="3"></figure>"#;
        let segments = segment(html);
        let text = buffer::render(&segments);
        let hints = opaque_hints(&text, &segments, &LineIndex::new(&text));
        assert_eq!(hints.len(), 1);
        assert_eq!(hints[0]["severity"], SEVERITY_HINT as u64);
        assert!(
            hints[0]["message"]
                .as_str()
                .unwrap()
                .contains("no Markdown form"),
            "{hints:?}"
        );
    }

    #[test]
    fn an_ordered_task_list_is_reported_as_a_task_list_degradation() {
        let segments = segment("<p>placeholder</p>");
        let text = "1. [x] a";
        let hints = task_list_degradation_hints(text, &segments, &LineIndex::new(text));
        assert_eq!(hints.len(), 1);
        assert_eq!(hints[0]["severity"], SEVERITY_WARNING as u64);
        assert!(
            hints[0]["message"]
                .as_str()
                .unwrap()
                .contains("no CKEditor form here"),
            "{hints:?}"
        );
    }

    #[test]
    fn fulltext_queries_cannot_break_out_of_their_quotes() {
        assert_eq!(fulltext_query("a\"b"), "\"ab\"");
    }

    #[test]
    fn fulltext_queries_neutralize_attribute_syntax_characters() {
        // `#`, `~`, and a bare `note.` all switch Trilium's lexer out of
        // fulltext mode when they appear unquoted -- see `lex.ts`. Wrapping
        // the whole token in quotes must keep them inert.
        for typed in ["#project", "~relation", "note.js", "c#"] {
            let query = fulltext_query(typed);
            assert!(query.starts_with('"') && query.ends_with('"'), "{query}");
        }
    }

    #[test]
    fn truncate_preview_passes_short_text_through_unchanged() {
        assert_eq!(
            truncate_preview("one\ntwo\nthree", 15),
            Some("one\ntwo\nthree".to_string())
        );
    }

    #[test]
    fn truncate_preview_cuts_long_text_with_an_ellipsis() {
        let text = (1..=20)
            .map(|n| n.to_string())
            .collect::<Vec<_>>()
            .join("\n");
        let preview = truncate_preview(&text, 15).unwrap();
        assert_eq!(preview.lines().count(), 16);
        assert_eq!(preview.lines().last(), Some("..."));
        assert_eq!(preview.lines().nth(14), Some("15"));
    }

    #[test]
    fn truncate_preview_is_none_for_blank_text() {
        assert_eq!(truncate_preview("   \n\n  ", 15), None);
        assert_eq!(truncate_preview("", 15), None);
    }

    #[test]
    fn canonical_uri_strips_a_title_suffix() {
        assert_eq!(
            canonical_uri("trilium://abc123/My Note"),
            "trilium://abc123"
        );
    }

    #[test]
    fn canonical_uri_is_a_no_op_on_an_already_bare_uri() {
        assert_eq!(canonical_uri("trilium://abc123"), "trilium://abc123");
    }

    #[test]
    fn canonical_uri_passes_through_an_unrelated_scheme_unchanged() {
        assert_eq!(
            canonical_uri("trilium-meta://abc123"),
            "trilium-meta://abc123"
        );
    }

    #[test]
    fn sanitize_title_replaces_a_slash_so_it_survives_a_tail_extraction() {
        assert_eq!(sanitize_title("Q1/Q2 Planning"), "Q1-Q2 Planning");
    }

    #[test]
    fn sanitize_title_strips_control_characters() {
        assert_eq!(sanitize_title("a\nb\tc\rd"), "a-b-c-d");
    }

    #[test]
    fn sanitize_title_leaves_ordinary_text_untouched() {
        assert_eq!(sanitize_title("Meeting Notes"), "Meeting Notes");
    }

    #[test]
    fn slug_path_joins_ancestors_and_title() {
        assert_eq!(
            slug_path(
                &["Waystone".to_string(), "People".to_string()],
                "Alice Smith"
            ),
            "waystone-people-alice-smith"
        );
    }

    #[test]
    fn slug_path_collapses_punctuation_runs() {
        assert_eq!(slug_path(&[], "Q1/Q2 Planning!!"), "q1-q2-planning");
    }

    #[test]
    fn slug_path_is_just_the_title_with_no_ancestors() {
        assert_eq!(slug_path(&[], "Waystone"), "waystone");
    }

    #[test]
    fn value_matches_type_accepts_a_well_formed_number() {
        assert!(value_matches_type("1.10", "number"));
        assert!(!value_matches_type("one point ten", "number"));
    }

    fn field_at(line: usize, column: usize) -> meta::Field {
        meta::Field {
            kind: meta::Kind::Label,
            name: "x".into(),
            value: "y".into(),
            inheritable: false,
            at: Some((line, column)),
        }
    }

    #[test]
    fn field_range_converts_a_1_based_marker_to_a_0_based_lsp_range() {
        assert_eq!(field_range(&field_at(3, 5)), ((2, 4), (2, 5)));
    }

    #[test]
    fn field_range_falls_back_to_the_top_of_the_document_with_no_position() {
        let mut field = field_at(3, 5);
        field.at = None;
        assert_eq!(field_range(&field), ((0, 0), (0, 1)));
    }

    #[test]
    fn relation_hints_places_a_title_at_the_end_of_a_bare_value_line() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  mentor: abc123\n";
        let mut titles = HashMap::new();
        titles.insert("abc123".to_string(), Some("Andre Selby".to_string()));
        let hints = relation_hints(text, &titles);
        assert_eq!(hints.len(), 1);
        assert_eq!(hints[0]["label"], "  Andre Selby");
        let line = text.lines().position(|l| l == "  mentor: abc123").unwrap() as u64;
        assert_eq!(hints[0]["position"]["line"], line);
        assert_eq!(
            hints[0]["position"]["character"],
            "  mentor: abc123".len() as u64
        );
    }

    #[test]
    fn relation_hints_places_a_title_after_each_list_item() {
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  isFriendOf:\n    - abc123\n    - def456\n";
        let mut titles = HashMap::new();
        titles.insert("abc123".to_string(), Some("Andre Selby".to_string()));
        titles.insert("def456".to_string(), None);
        let hints = relation_hints(text, &titles);
        assert_eq!(hints.len(), 2);
        assert_eq!(hints[0]["label"], "  Andre Selby");
        assert_eq!(hints[1]["label"], "  missing note");
    }

    #[test]
    fn relation_hints_skips_an_unresolved_id_gracefully() {
        // No entry in `titles` at all (not even `None`) -- as if the
        // lookup was never attempted -- must not panic or fabricate one.
        let text = "title: x\nnoteId: a\ntype: text\n\nrelations:\n  mentor: abc123\n";
        let hints = relation_hints(text, &HashMap::new());
        assert_eq!(hints[0]["label"], "  missing note");
    }

    #[test]
    fn value_matches_type_accepts_only_true_or_false_for_boolean() {
        assert!(value_matches_type("true", "boolean"));
        assert!(value_matches_type("false", "boolean"));
        assert!(!value_matches_type("yes", "boolean"));
    }

    #[test]
    fn value_matches_type_is_permissive_for_free_form_types() {
        assert!(value_matches_type("anything at all", "text"));
        assert!(value_matches_type("anything at all", "date"));
    }

    #[test]
    fn schema_section_lists_definitions_before_vocabulary_and_marks_which_is_which() {
        let mut definitions = HashMap::new();
        definitions.insert(
            (meta::Kind::Label, "todo".to_string()),
            index::Definition {
                promoted: true,
                multi: false,
                label_type: Some("boolean".to_string()),
            },
        );
        let vocabulary_names = vec!["draft".to_string(), "todo".to_string()];

        let section = schema_section(meta::Kind::Label, &definitions, &vocabulary_names);
        let items = section.as_array().unwrap();

        // "todo" has a definition and must not also appear as a plain
        // vocabulary entry -- it names the same label, not two different
        // things to write.
        assert_eq!(items.len(), 2, "{items:?}");
        assert_eq!(items[0]["name"], "todo");
        assert_eq!(items[0]["defined"], true);
        assert_eq!(items[0]["detail"], "promoted, single, boolean");
        assert_eq!(items[1]["name"], "draft");
        assert_eq!(items[1]["defined"], false);
        assert!(items[1]["detail"].is_null());
    }

    #[test]
    fn schema_section_ignores_a_definition_of_the_other_kind() {
        let mut definitions = HashMap::new();
        definitions.insert(
            (meta::Kind::Relation, "template".to_string()),
            index::Definition::default(),
        );
        let section = schema_section(meta::Kind::Label, &definitions, &[]);
        assert_eq!(section.as_array().unwrap().len(), 0);
    }
}
