//! Blocking ETAPI client for Trilium.
//!
//! Scope is deliberately narrow: the endpoints the note-editing loop needs.
//! Verified against TriliumNext 0.104.1 (`apps/server/src/etapi/`).

use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("http transport: {0}")]
    Http(#[from] reqwest::Error),
    #[error("etapi {status} {code}: {message}")]
    Api {
        status: u16,
        code: String,
        message: String,
    },
    #[error("note '{0}' is protected and not reachable over ETAPI")]
    Protected(String),
}

pub type Result<T> = std::result::Result<T, Error>;

/// Shape returned by `mapNoteToPojo`. Only the fields we act on are modelled.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Note {
    pub note_id: String,
    pub title: String,
    #[serde(rename = "type")]
    pub note_type: String,
    pub mime: String,
    /// Content hash. The only handle we get for staleness detection -- ETAPI
    /// exposes no `ETag` and honours no `If-Match`.
    pub blob_id: String,
    pub is_protected: bool,
    #[serde(default)]
    pub parent_note_ids: Vec<String>,
    #[serde(default)]
    pub child_note_ids: Vec<String>,
    #[serde(default)]
    pub attributes: Vec<Attribute>,
    pub date_modified: Option<String>,
}

/// A label (`#name=value`) or relation (`~name=targetNoteId`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Attribute {
    pub attribute_id: String,
    pub note_id: String,
    #[serde(rename = "type")]
    pub attribute_type: String,
    pub name: String,
    #[serde(default)]
    pub value: String,
    #[serde(default)]
    pub is_inheritable: bool,
}

impl Attribute {
    pub fn is_label(&self) -> bool {
        self.attribute_type == "label"
    }

    pub fn is_relation(&self) -> bool {
        self.attribute_type == "relation"
    }
}

#[derive(Debug, Deserialize)]
struct SearchResponse {
    results: Vec<Note>,
}

/// Shape returned by `POST /etapi/create-note`.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreatedNote {
    pub note: Note,
    pub branch: Branch,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Branch {
    pub branch_id: String,
    pub note_id: String,
    pub parent_note_id: String,
}

#[derive(Debug, Deserialize)]
struct ApiError {
    status: u16,
    code: String,
    message: String,
}

#[derive(Debug, Serialize)]
struct RevisionRequest<'a> {
    description: &'a str,
}

#[derive(Clone)]
pub struct Client {
    base: String,
    token: String,
    http: reqwest::blocking::Client,
}

impl Client {
    /// `base` is the server root, e.g. `https://trilium.example.com`.
    pub fn new(base: impl Into<String>, token: impl Into<String>) -> Result<Self> {
        Ok(Self {
            base: base.into().trim_end_matches('/').to_string(),
            token: token.into(),
            http: reqwest::blocking::Client::builder().build()?,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}/etapi{}", self.base, path)
    }

    /// The server root this client talks to, e.g. `https://trilium.example.com`.
    /// Used to key the on-disk note index cache per server.
    pub fn base_url(&self) -> &str {
        &self.base
    }

    fn request(&self, method: reqwest::Method, path: &str) -> reqwest::blocking::RequestBuilder {
        // Trilium accepts the bare token, `Bearer <token>`, or basic auth with
        // the token in the password field. The bare form is the canonical one.
        self.http
            .request(method, self.url(path))
            .header(reqwest::header::AUTHORIZATION, &self.token)
    }

    fn check(resp: reqwest::blocking::Response) -> Result<reqwest::blocking::Response> {
        if resp.status().is_success() {
            return Ok(resp);
        }
        let status = resp.status().as_u16();
        match resp.json::<ApiError>() {
            Ok(e) => Err(Error::Api {
                status: e.status,
                code: e.code,
                message: e.message,
            }),
            Err(_) => Err(Error::Api {
                status,
                code: "UNKNOWN".into(),
                message: format!("non-JSON error body (HTTP {status})"),
            }),
        }
    }

    pub fn app_info(&self) -> Result<serde_json::Value> {
        let resp = Self::check(self.request(reqwest::Method::GET, "/app-info").send()?)?;
        Ok(resp.json()?)
    }

    pub fn note(&self, note_id: &str) -> Result<Note> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, &format!("/notes/{note_id}"))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Raw note content. For `text` notes this is CKEditor HTML.
    pub fn content(&self, note_id: &str) -> Result<String> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, &format!("/notes/{note_id}/content"))
                .send()?,
        )?;
        Ok(resp.text()?)
    }

    /// Overwrite note content.
    ///
    /// Unconditional: ETAPI has no `If-Match` support, so this is last-write-wins
    /// at the protocol level. Callers wanting staleness detection must compare
    /// [`Note::blob_id`] beforehand and accept the residual race.
    pub fn set_content(&self, note_id: &str, content: &str) -> Result<()> {
        Self::check(
            self.request(reqwest::Method::PUT, &format!("/notes/{note_id}/content"))
                .header(reqwest::header::CONTENT_TYPE, "text/plain")
                .body(content.to_string())
                .send()?,
        )?;
        Ok(())
    }

    /// Force a revision snapshot.
    ///
    /// Distinct from Trilium's automatic `saveRevisionIfNeeded`, which is
    /// debounced by the `revisionSnapshotTimeInterval` option and may therefore
    /// decline to snapshot. This endpoint calls `note.saveRevision()` directly
    /// and always creates one, which is what makes it usable as a safety net.
    pub fn snapshot(&self, note_id: &str, description: &str) -> Result<()> {
        Self::check(
            self.request(reqwest::Method::POST, &format!("/notes/{note_id}/revision"))
                .json(&RevisionRequest { description })
                .send()?,
        )?;
        Ok(())
    }

    /// Full-text / attribute search using Trilium's own query syntax.
    pub fn search(&self, query: &str, limit: Option<u32>) -> Result<Vec<Note>> {
        let mut req = self
            .request(reqwest::Method::GET, "/notes")
            .query(&[("search", query)]);
        if let Some(limit) = limit {
            req = req.query(&[("limit", limit.to_string())]);
        }
        let resp = Self::check(req.send()?)?;
        Ok(resp.json::<SearchResponse>()?.results)
    }

    /// Search restricted to titles and ancestor paths, skipping the content
    /// scan (`fastSearch`) that `search` would otherwise also run. This is
    /// what Trilium's own note-link autocomplete uses, and what gives it
    /// fuzzy title matching and matches against the note's ancestor chain --
    /// neither of which a plain attribute comparison on `note.title` can do.
    pub fn search_notes(&self, query: &str, limit: Option<u32>) -> Result<Vec<Note>> {
        let mut req = self
            .request(reqwest::Method::GET, "/notes")
            .query(&[("search", query), ("fastSearch", "true")]);
        if let Some(limit) = limit {
            req = req.query(&[("limit", limit.to_string())]);
        }
        let resp = Self::check(req.send()?)?;
        Ok(resp.json::<SearchResponse>()?.results)
    }

    /// Every note in the vault, for a local path index. `%=` is Trilium's
    /// regex comparator (`build_comparator.ts`); an unescaped `.` matches any
    /// single character, so this selects every note with a non-empty id --
    /// which is all of them. `includeHiddenNotes` is left at its ETAPI
    /// default (unavailable, effectively false), so rhizome's own hidden
    /// system notes stay out of a link picker built from this.
    pub fn all_notes(&self) -> Result<Vec<Note>> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, "/notes")
                .query(&[
                    ("search", "note.noteId %= '.'"),
                    ("fastSearch", "true"),
                    ("includeArchivedNotes", "true"),
                    ("limit", "20000"),
                ])
                .send()?,
        )?;
        Ok(resp.json::<SearchResponse>()?.results)
    }

    /// Change a note's title.
    ///
    /// Unlike content writes, Trilium runs `saveRevisionIfNeeded` for this
    /// itself, so no forced snapshot is needed here.
    pub fn rename(&self, note_id: &str, title: &str) -> Result<Note> {
        let resp = Self::check(
            self.request(reqwest::Method::PATCH, &format!("/notes/{note_id}"))
                .json(&serde_json::json!({ "title": title }))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Attach a label (`#name=value`) or relation (`~name=targetNoteId`).
    pub fn create_attribute(
        &self,
        note_id: &str,
        attribute_type: &str,
        name: &str,
        value: &str,
        inheritable: bool,
    ) -> Result<Attribute> {
        let resp = Self::check(
            self.request(reqwest::Method::POST, "/attributes")
                .json(&serde_json::json!({
                    "noteId": note_id,
                    "type": attribute_type,
                    "name": name,
                    "value": value,
                    "isInheritable": inheritable,
                }))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    pub fn update_attribute(&self, attribute_id: &str, value: &str) -> Result<()> {
        Self::check(
            self.request(
                reqwest::Method::PATCH,
                &format!("/attributes/{attribute_id}"),
            )
            .json(&serde_json::json!({ "value": value }))
            .send()?,
        )?;
        Ok(())
    }

    pub fn delete_attribute(&self, attribute_id: &str) -> Result<()> {
        Self::check(
            self.request(
                reqwest::Method::DELETE,
                &format!("/attributes/{attribute_id}"),
            )
            .send()?,
        )?;
        Ok(())
    }

    /// Get-or-create the day note for `date` (`YYYY-MM-DD`). Trilium creates
    /// it lazily on first request, so this is not a pure read.
    pub fn day_note(&self, date: &str) -> Result<Note> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, &format!("/calendar/days/{date}"))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Get-or-create today's inbox note (`date` is `YYYY-MM-DD`).
    pub fn inbox(&self, date: &str) -> Result<Note> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, &format!("/inbox/{date}"))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Create a new note under `parent_note_id`.
    pub fn create_note(
        &self,
        parent_note_id: &str,
        title: &str,
        note_type: &str,
        content: &str,
    ) -> Result<CreatedNote> {
        let resp = Self::check(
            self.request(reqwest::Method::POST, "/create-note")
                .json(&serde_json::json!({
                    "parentNoteId": parent_note_id,
                    "title": title,
                    "type": note_type,
                    "content": content,
                }))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Look up a branch by id, to confirm one actually exists (and connects
    /// the note and parent a caller expects) before an irreversible
    /// `delete_branch`. `branch_id` is deterministic
    /// (`${parentNoteId}_${noteId}`, see `BBranch::beforeSaving` upstream),
    /// but that is an internal implementation detail rather than a
    /// documented part of ETAPI -- this turns the assumption into a checked
    /// precondition instead of a blind guess.
    pub fn get_branch(&self, branch_id: &str) -> Result<Branch> {
        let resp = Self::check(
            self.request(reqwest::Method::GET, &format!("/branches/{branch_id}"))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Place `note_id` under `parent_note_id`. If a branch between the two
    /// already exists, Trilium updates it in place rather than erroring --
    /// so this both clones a note to a new parent and is the second half of
    /// a move (create the new branch, then delete the old one).
    pub fn create_branch(&self, note_id: &str, parent_note_id: &str) -> Result<Branch> {
        let resp = Self::check(
            self.request(reqwest::Method::POST, "/branches")
                .json(&serde_json::json!({
                    "noteId": note_id,
                    "parentNoteId": parent_note_id,
                }))
                .send()?,
        )?;
        Ok(resp.json()?)
    }

    /// Remove one placement of a note. If this is the note's last branch,
    /// Trilium deletes the note itself -- callers must check `clone_count`
    /// (or otherwise be certain another branch survives) before calling
    /// this, since ETAPI gives no warning and the deletion is otherwise
    /// silent.
    pub fn delete_branch(&self, branch_id: &str) -> Result<()> {
        Self::check(
            self.request(reqwest::Method::DELETE, &format!("/branches/{branch_id}"))
                .send()?,
        )?;
        Ok(())
    }

    /// Delete a note everywhere (every branch, i.e. every clone). Soft --
    /// Trilium keeps it recoverable via `POST /notes/{id}/undelete` until
    /// erase runs.
    pub fn delete_note(&self, note_id: &str) -> Result<()> {
        Self::check(
            self.request(reqwest::Method::DELETE, &format!("/notes/{note_id}"))
                .send()?,
        )?;
        Ok(())
    }
}

/// The id Trilium assigns a branch between `parent_note_id` and `note_id`.
/// Deterministic (`BBranch::beforeSaving` upstream sets exactly this), which
/// is what lets a caller target `delete_branch`/`get_branch` without a
/// lookup pass over `Note::parent_branch_ids` first.
pub fn branch_id(parent_note_id: &str, note_id: &str) -> String {
    format!("{parent_note_id}_{note_id}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn branch_id_joins_parent_and_note_with_an_underscore() {
        assert_eq!(branch_id("root", "abc123"), "root_abc123");
    }
}
