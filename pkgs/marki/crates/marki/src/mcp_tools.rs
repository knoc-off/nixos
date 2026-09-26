//! Tool logic behind `marki mcp`, kept synchronous and transport-free so it
//! can be unit-tested directly. [`crate::mcp`] wraps it for rmcp.
//!
//! Every path an agent passes is relative to the cards dir and confined to
//! it; card writes go through fmt + a render check before touching disk;
//! pushes are simulate-then-confirm (see [`Project::simulate`]).

use anyhow::{Context, Result, bail, ensure};
use serde::Serialize;
use std::path::{Component, Path, PathBuf};

use crate::config::MARKI_DIR;
use crate::fmt::format_card;
use crate::id::mint_id;
use crate::note_parser::parse_note;
use crate::project::Project;
use crate::scan::{deck_for_note, scan_dir_v2};
use crate::sync::Outcome;

/// Rows returned by `query` before truncation.
const QUERY_ROW_LIMIT: usize = 200;

pub struct Handler {
    pub project: Project,
}

#[derive(Serialize)]
pub struct CardSummary {
    pub path: String,
    pub id: Option<String>,
    pub model: String,
    pub deck: String,
    /// First line of the note, for orientation.
    pub title: String,
}

#[derive(Serialize)]
pub struct PushReport {
    /// `status` (read-only plan), `simulation` (dry run on copies) or
    /// `push` (written).
    pub kind: &'static str,
    pub ok: bool,
    /// For `simulation`: pass to a confirmed push.
    #[serde(skip_serializing_if = "String::is_empty")]
    pub plan_hash: String,
    pub changes: Vec<ChangeLine>,
    /// Cards that failed to render (they are left untouched in Anki).
    pub errors: Vec<String>,
    /// For `simulation`: what would go wrong beyond render errors.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub problems: Vec<String>,
    /// For `push`: media, collection, server, git -- each ok/error/skipped.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub steps: Vec<crate::project::Step>,
    /// Card files changed on disk but not committed to git.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub uncommitted: Vec<String>,
    /// Read from a snapshot because the sync server holds the files.
    pub snapshot: bool,
    pub full_sync_required: bool,
}

#[derive(Serialize)]
pub struct ChangeLine {
    pub kind: &'static str,
    pub path: String,
    pub detail: String,
}

impl Handler {
    pub fn new(project: Project) -> Self {
        Self { project }
    }

    fn root(&self) -> &Path {
        &self.project.cfg.cards_dir
    }

    /// Resolve an agent-supplied relative path inside the cards dir. Rejects
    /// absolute paths, `..`, and anything under `.marki/` (models and media
    /// have their own tools).
    pub fn card_path(&self, rel: &str) -> Result<PathBuf> {
        let p = safe_rel(rel)?;
        ensure!(
            p.extension().is_some_and(|e| e == "md"),
            "card paths must end in .md: {rel}"
        );
        ensure!(
            !p.starts_with(MARKI_DIR),
            "{rel}: use the model/media tools for files under {MARKI_DIR}/"
        );
        Ok(self.root().join(p))
    }

    fn rel(&self, p: &Path) -> String {
        p.strip_prefix(self.root()).unwrap_or(p).display().to_string()
    }

    fn models_dir(&self) -> PathBuf {
        self.project.cfg.resolved_models_dir()
    }

    /// Overview for an agent starting work: models (with their card types and
    /// descriptions), decks in use with counts, and the media dirs.
    pub fn context(&mut self) -> Result<serde_json::Value> {
        let notes = scan_dir_v2(self.root())?;
        let mut decks: std::collections::BTreeMap<String, usize> = Default::default();
        let mut models_used: std::collections::BTreeMap<String, usize> = Default::default();
        for sn in &notes {
            *decks.entry(deck_for_note(self.root(), &sn.note)).or_default() += 1;
            *models_used.entry(sn.note.model.clone()).or_default() += 1;
        }
        let mut models = vec![
            serde_json::json!({"name": "basic", "builtin": true, "cards": ["Card"],
                "describe": "Section 1 is the front, section 2 the back."}),
            serde_json::json!({"name": "cloze", "builtin": true,
                "describe": "Mark answers **bold**/*italic* and add #cloze; one card per deletion."}),
        ];
        for name in self.model_names()? {
            let m = self.project.engine.load_model(&name);
            models.push(match m {
                Ok(m) => serde_json::json!({"name": name, "cards": m.card_names,
                    "describe": m.describe}),
                Err(e) => serde_json::json!({"name": name, "error": format!("{e:#}")}),
            });
        }
        let media = std::fs::read_dir(self.project.cfg.builtin_media_dir())
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter(|e| e.path().is_dir())
                    .map(|e| e.file_name().to_string_lossy().into_owned())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        Ok(serde_json::json!({
            "cards": notes.len(),
            "decks": decks,
            "models_in_use": models_used,
            "models": models,
            "media_dirs": media,
            "media_sources": self.project.cfg.media_sources.keys().collect::<Vec<_>>(),
        }))
    }

    fn model_names(&self) -> Result<Vec<String>> {
        let mut out: Vec<String> = std::fs::read_dir(self.models_dir())
            .map(|rd| {
                rd.filter_map(|e| e.ok())
                    .filter_map(|e| {
                        let p = e.path();
                        (p.extension()? == "lua").then(|| p.file_stem()?.to_str().map(String::from))?
                    })
                    .collect()
            })
            .unwrap_or_default();
        out.sort();
        Ok(out)
    }

    /// Case-insensitive substring search over path and source. Empty query
    /// lists everything (capped).
    pub fn search_cards(&self, query: &str, limit: usize) -> Result<Vec<CardSummary>> {
        let q = query.to_lowercase();
        let mut out = Vec::new();
        let mut notes = scan_dir_v2(self.root())?;
        notes.sort_by(|a, b| a.path.cmp(&b.path));
        for sn in notes {
            let rel = self.rel(&sn.path);
            if !q.is_empty()
                && !rel.to_lowercase().contains(&q)
                && !sn.source.to_lowercase().contains(&q)
            {
                continue;
            }
            out.push(CardSummary {
                deck: deck_for_note(self.root(), &sn.note),
                id: sn.note.id.clone(),
                model: sn.note.model.clone(),
                title: sn.source.lines().find(|l| !l.trim().is_empty()).unwrap_or("").chars().take(80).collect(),
                path: rel,
            });
            if out.len() >= limit {
                break;
            }
        }
        Ok(out)
    }

    pub fn read_card(&self, rel: &str) -> Result<String> {
        let p = self.card_path(rel)?;
        std::fs::read_to_string(&p).with_context(|| format!("read {rel}"))
    }

    /// Render a card (saved file or draft `source`) with an optional draft
    /// model. Returns the HTML page plus per-card JSON.
    pub fn preview(
        &mut self,
        rel: &str,
        source: Option<&str>,
        model_lua: Option<&str>,
        model_css: Option<&str>,
    ) -> Result<serde_json::Value> {
        let path = self.card_path(rel)?;
        let source = match source {
            Some(s) => s.to_string(),
            None => std::fs::read_to_string(&path).with_context(|| format!("read {rel}"))?,
        };
        let model = parse_note(&source, path.clone()).model;
        if let Some(lua) = model_lua {
            self.project.engine.set_draft(&model, lua)?;
        }
        let result = self.project.preview(&path, &source);
        self.project.engine.clear_drafts();
        let mut p = result?;
        if let Some(css) = model_css {
            p.note.spec.css = css.to_string();
        }
        Ok(serde_json::json!({
            "model": model,
            "deck": deck_for_note(self.root(), &parse_note(&source, path.clone())),
            "cards": p.cards,
            "errors": p.note.errors,
            "assets": p.note.assets.iter().map(|a| &a.filename).collect::<Vec<_>>(),
            "css": p.note.spec.css,
        }))
    }

    /// Format, validate and write a card. A new file gets a fresh id; an
    /// existing file may only be replaced when `expected_id` matches its
    /// current `#id` (so an agent can't clobber a card it didn't read).
    /// Returns the written source.
    pub fn write_card(&mut self, rel: &str, source: &str, expected_id: Option<&str>) -> Result<String> {
        let path = self.card_path(rel)?;
        if path.exists() {
            let current = parse_note(&std::fs::read_to_string(&path)?, path.clone()).id;
            match (current.as_deref(), expected_id) {
                (Some(c), Some(e)) if c == e => {}
                (cur, _) => bail!(
                    "{rel} exists (id {}); read it and pass expected_id to overwrite",
                    cur.unwrap_or("none")
                ),
            }
        }
        let formatted = format_card(source, &mint_id());
        let note = parse_note(&formatted, path.clone());
        ensure!(note.warnings.is_empty(), "card warnings: {}", note.warnings.join("; "));
        if let (Some(e), Some(id)) = (expected_id, &note.id) {
            ensure!(e == id, "source carries #id({id}) but expected_id is {e}; keep the id");
        }
        // Duplicate id elsewhere in the tree would make two files claim one note.
        let id = note.id.clone().unwrap_or_default();
        for sn in scan_dir_v2(self.root())? {
            if sn.path != path && sn.note.id.as_deref() == Some(id.as_str()) {
                bail!("#id({id}) already used by {}", self.rel(&sn.path));
            }
        }
        let preview = self.project.preview(&path, &formatted)?;
        ensure!(
            preview.note.errors.is_empty(),
            "card does not render: {}",
            preview.note.errors.join("; ")
        );
        ensure!(!preview.cards.is_empty(), "card generates no cards (empty front?)");
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        std::fs::write(&path, &formatted).with_context(|| format!("write {rel}"))?;
        Ok(formatted)
    }

    /// Save a media file into `.marki/media/<dir>/<name>`. Referenced from
    /// cards as ```media src = "<dir>/<stem>"```.
    pub fn add_media(&self, dir: &str, name: &str, bytes: &[u8]) -> Result<String> {
        let rel = safe_rel(&format!("{dir}/{name}"))?;
        ensure!(rel.components().count() >= 2, "media needs a directory: dir/name.ext");
        let ext = rel.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
        ensure!(
            ["svg", "png", "webp", "jpg", "jpeg", "gif", "mp3", "ogg", "m4a", "wav"].contains(&ext.as_str()),
            "unsupported media extension .{ext}"
        );
        ensure!(bytes.len() <= 20 << 20, "media file over 20 MiB");
        let dest = self.project.cfg.builtin_media_dir().join(&rel);
        if let Some(d) = dest.parent() {
            std::fs::create_dir_all(d)?;
        }
        std::fs::write(&dest, bytes)?;
        let stem = rel.with_extension("");
        Ok(format!("src = \"{}\"", stem.display()))
    }

    /// Cards whose source mentions `needle` (an id, a media name, a tag).
    pub fn find(&self, needle: &str) -> Result<Vec<String>> {
        ensure!(!needle.trim().is_empty(), "empty search");
        let mut out: Vec<String> = scan_dir_v2(self.root())?
            .into_iter()
            .filter(|sn| sn.source.contains(needle) || sn.note.id.as_deref() == Some(needle))
            .map(|sn| self.rel(&sn.path))
            .collect();
        out.sort();
        Ok(out)
    }

    pub fn read_model(&mut self, name: &str) -> Result<serde_json::Value> {
        check_model_name(name)?;
        if let Some(lua) = builtin_model_lua(name) {
            return Ok(serde_json::json!({
                "name": name,
                "builtin": true,
                "note": "built in, not editable: this Lua is an equivalent example to copy from",
                "lua": lua,
                "card_usage": self.usage(name)?,
            }));
        }
        let dir = self.models_dir();
        let lua = std::fs::read_to_string(dir.join(format!("{name}.lua"))).map_err(|_| {
            anyhow::anyhow!(
                "no model {name}; models are {}",
                ["basic", "cloze"]
                    .into_iter()
                    .map(String::from)
                    .chain(self.model_names().unwrap_or_default())
                    .collect::<Vec<_>>()
                    .join(", ")
            )
        })?;
        let css = std::fs::read_to_string(dir.join(format!("{name}.css"))).ok();
        let usage = self.usage(name)?;
        Ok(serde_json::json!({"name": name, "lua": lua, "css": css, "card_usage": usage}))
    }

    fn usage(&self, name: &str) -> Result<Vec<serde_json::Value>> {
        let Ok(view) = self.project.read_view() else {
            return Ok(vec![]);
        };
        Ok(view
            .col
            .template_usage(&format!("marki:{name}"))?
            .into_iter()
            .map(|(t, cards, reviews)| serde_json::json!({"card": t, "cards": cards, "reviews": reviews}))
            .collect())
    }

    /// Validate a model (compiles, has describe(), renders every note that
    /// uses it) and save it. Returns what saving does to the collection:
    /// the per-card-type usage before, and the simulated push afterwards
    /// (which fails loudly on a refused card removal).
    pub fn write_model(&mut self, name: &str, lua: &str, css: Option<&str>) -> Result<serde_json::Value> {
        check_model_name(name)?;
        ensure!(!["basic", "cloze"].contains(&name), "{name} is built in");
        let compiled = self.project.engine.set_draft(name, lua);
        let check = compiled.and_then(|m| {
            ensure!(
                m.describe.as_deref().is_some_and(|d| !d.trim().is_empty()),
                "model must define M.describe() returning a short description"
            );
            let mut failures = Vec::new();
            for sn in scan_dir_v2(self.root())?.into_iter().filter(|sn| sn.note.model == name) {
                match self.project.preview(&sn.path, &sn.source) {
                    Ok(p) if p.note.errors.is_empty() => {}
                    Ok(p) => failures.push(format!("{}: {}", self.rel(&sn.path), p.note.errors.join("; "))),
                    Err(e) => failures.push(format!("{}: {e:#}", self.rel(&sn.path))),
                }
            }
            ensure!(failures.is_empty(), "notes fail to render:\n{}", failures.join("\n"));
            Ok(m.card_names.clone())
        });
        self.project.engine.clear_drafts();
        let card_names = check?;

        let before = self.usage(name)?;
        let dir = self.models_dir();
        std::fs::create_dir_all(&dir)?;
        std::fs::write(dir.join(format!("{name}.lua")), lua)?;
        if let Some(css) = css {
            std::fs::write(dir.join(format!("{name}.css")), css)?;
        }
        self.project.engine.invalidate(name);
        Ok(serde_json::json!({
            "saved": name,
            "cards": card_names,
            "card_usage_before": before,
            "next": "call marki_push to simulate; renamed card types need M.renames, dropped ones M.allow_card_removal",
        }))
    }

    /// Everything that differs between the cards and Anki: pending
    /// models/notes/media plus uncommitted card files. Clean means all three
    /// agree.
    pub fn status(&mut self) -> Result<PushReport> {
        let (o, snapshot) = self.project.plan(false)?;
        let uncommitted = git_dirty(self.root())?;
        let mut r = self.report("status", &o, vec![], String::new(), vec![], snapshot);
        r.ok = r.ok && r.changes.is_empty() && uncommitted.is_empty();
        r.uncommitted = uncommitted;
        Ok(r)
    }

    /// Without `confirm`: simulate and return a plan hash. With it: push if
    /// the plan still matches, then commit the cards repo.
    pub fn push(&mut self, confirm: bool, plan_hash: Option<&str>) -> Result<PushReport> {
        if !confirm {
            let sim = self.project.simulate(false)?;
            let mut problems = sim.problems;
            if let Err(e) = git_usable(self.root()) {
                problems.push(format!("git: {e:#}"));
            }
            return Ok(self.report("simulation", &sim.outcome, problems, sim.plan_hash, vec![], false));
        }
        let hash = plan_hash.context("confirm requires the plan_hash from a simulation")?;
        let pushed = self.project.push(Some(hash), false)?;
        let mut steps = pushed.steps.clone();
        // Commit whenever the collection took the cards, even if a later step
        // (server restart) failed: the repo should record what Anki now has.
        steps.push(if pushed.collection_written() {
            match git_commit(self.root(), &pushed.outcome) {
                Ok(Some(msg)) => crate::project::Step::ok("git", msg),
                Ok(None) => crate::project::Step::skipped("git", "nothing to commit"),
                Err(e) => crate::project::Step::error("git", &e),
            }
        } else {
            crate::project::Step::skipped("git", "collection not written")
        });
        let mut r = self.report("push", &pushed.outcome, vec![], pushed.plan_hash.clone(), steps, false);
        r.full_sync_required = pushed.schema_changed;
        r.ok = pushed.ok() && r.steps.iter().all(|s| s.status != "error");
        Ok(r)
    }

    fn report(
        &self,
        kind: &'static str,
        o: &Outcome,
        problems: Vec<String>,
        plan_hash: String,
        steps: Vec<crate::project::Step>,
        snapshot: bool,
    ) -> PushReport {
        PushReport {
            kind,
            ok: o.errors.is_empty() && problems.is_empty(),
            plan_hash,
            snapshot,
            uncommitted: vec![],
            full_sync_required: o.changes.iter().any(|c| c.full_sync),
            changes: o
                .changes
                .iter()
                .map(|c| ChangeLine {
                    kind: (&c.kind).into(),
                    path: match (&c.path, &c.kind) {
                        (Some(p), _) => self.rel(p),
                        (None, crate::sync::ChangeKind::Orphan) => format!("#id({})", c.id),
                        (None, _) => c.id.clone(),
                    },
                    detail: c.detail.clone(),
                })
                .collect(),
            errors: o.errors.clone(),
            problems,
            steps,
        }
    }

    /// Card files whose Anki cards carry `flag` (1 red, 2 orange, 3 green,
    /// 4 blue, 5 pink, 6 turquoise, 7 purple).
    pub fn flagged(&self, flag: u8) -> Result<Vec<serde_json::Value>> {
        ensure!((1..=7).contains(&flag), "flag must be 1..7");
        let view = self.project.read_view()?;
        let mut stmt = view.col.conn().prepare(
            "SELECT n.guid, count(*) FROM cards c JOIN notes n ON n.id=c.nid \
             WHERE (c.flags & 7) = ?1 GROUP BY n.guid",
        )?;
        let rows: Vec<(String, i64)> = stmt
            .query_map([flag], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<rusqlite::Result<_>>()?;
        let paths = self.paths_by_id()?;
        Ok(rows
            .into_iter()
            .map(|(guid, n)| {
                serde_json::json!({"path": paths.get(&guid), "id": guid, "flagged_cards": n})
            })
            .collect())
    }

    fn paths_by_id(&self) -> Result<std::collections::HashMap<String, String>> {
        Ok(scan_dir_v2(self.root())?
            .into_iter()
            .filter_map(|sn| Some((sn.note.id.clone()?, self.rel(&sn.path))))
            .collect())
    }

    /// Read-only SQL over a snapshot of the collection. A `guid` column gets
    /// a sibling `path` column mapping it back to the card file.
    pub fn query(&self, sql: &str) -> Result<serde_json::Value> {
        let view = self.project.read_view()?;
        let dir = crate::project::TempDir::new("query")?;
        let snap = dir.path().join("snapshot.anki2");
        {
            view.col.backup(&snap)?;
            drop(view);
            let conn = rusqlite::Connection::open_with_flags(
                &snap,
                rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
            )?;
            // Notes/cards use Anki's `unicase` collation in indexes.
            conn.create_collation("unicase", |a, b| a.to_lowercase().cmp(&b.to_lowercase()))?;
            let mut stmt = conn.prepare(sql)?;
            ensure!(stmt.readonly(), "only read-only statements are allowed");
            let cols: Vec<String> = stmt.column_names().iter().map(|s| s.to_string()).collect();
            let guid_col = cols.iter().position(|c| c == "guid");
            let paths = if guid_col.is_some() { self.paths_by_id()? } else { Default::default() };
            let mut rows = stmt.query([])?;
            let mut out = Vec::new();
            let mut truncated = false;
            while let Some(row) = rows.next()? {
                if out.len() == QUERY_ROW_LIMIT {
                    truncated = true;
                    break;
                }
                let mut obj = serde_json::Map::new();
                for (i, c) in cols.iter().enumerate() {
                    use rusqlite::types::ValueRef;
                    let v = match row.get_ref(i)? {
                        ValueRef::Null => serde_json::Value::Null,
                        ValueRef::Integer(n) => n.into(),
                        ValueRef::Real(f) => f.into(),
                        ValueRef::Text(t) => String::from_utf8_lossy(t).into_owned().into(),
                        ValueRef::Blob(b) => format!("<blob {} bytes>", b.len()).into(),
                    };
                    if Some(i) == guid_col {
                        let path = v.as_str().and_then(|g| paths.get(g)).cloned();
                        obj.insert("path".into(), path.into());
                    }
                    obj.insert(c.clone(), v);
                }
                out.push(serde_json::Value::Object(obj));
            }
            Ok(serde_json::json!({"rows": out, "truncated": truncated}))
        }
    }
}

/// Lua equivalents of the built-in models, as examples for authors.
fn builtin_model_lua(name: &str) -> Option<&'static str> {
    match name {
        "basic" => Some(
            r#"local M = {}
M.card_names = { "Card" }
function M.describe() return "Section 1 is the front, section 2 the back." end
-- The answer side shows only CardBack (no {{FrontSide}}), so the
-- built-in's back is section 2 alone.
function M.generate(note, ctx)
  return { CardFront = ctx:section_html(note, 1), CardBack = ctx:section_html(note, 2) }
end
return M"#,
        ),
        // Cloze can't be written in Lua (it needs Anki's cloze note type);
        // this shows how the built-in reads a note.
        "cloze" => Some(
            r#"-- Not expressible as a Lua model: cloze needs Anki's cloze note
-- type (one card per {{cN::}} number). The built-in turns each **bold** /
-- *italic* span of a #cloze note into {{c1::}}, {{c2::}}, ... in the Text
-- field, and section 2 (after ---) becomes Back Extra. Write cloze cards
-- as markdown with #cloze; never write {{c1::}} by hand."#,
        ),
        _ => None,
    }
}

fn check_model_name(name: &str) -> Result<()> {
    ensure!(
        !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'),
        "model names are [A-Za-z0-9_-]"
    );
    Ok(())
}

/// A relative path with only normal components.
fn safe_rel(rel: &str) -> Result<PathBuf> {
    let p = PathBuf::from(rel);
    ensure!(
        !rel.is_empty() && p.components().all(|c| matches!(c, Component::Normal(_))),
        "path must be relative, without `..`: {rel}"
    );
    Ok(p)
}

fn git(root: &Path, args: &[&str]) -> Result<std::process::Output> {
    std::process::Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .context("run git")
}

/// Whether the cards dir is a repo git will operate on. `Ok(false)` only
/// for a plain directory; anything else git refuses (ownership, missing
/// binary, broken repo) is an error, never a silent skip.
fn git_repo(root: &Path) -> Result<bool> {
    if !root.join(".git").exists() {
        return Ok(false);
    }
    let out = git(root, &["rev-parse", "--is-inside-work-tree"])?;
    ensure!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr).trim());
    Ok(true)
}

/// A push will be able to commit: the repo is usable and has an identity.
fn git_usable(root: &Path) -> Result<()> {
    if !git_repo(root)? {
        return Ok(());
    }
    let out = git(root, &["var", "GIT_COMMITTER_IDENT"])?;
    ensure!(out.status.success(), "no committer identity: {}", String::from_utf8_lossy(&out.stderr).trim());
    Ok(())
}

/// Uncommitted changes under the cards dir (`git status --porcelain`).
fn git_dirty(root: &Path) -> Result<Vec<String>> {
    if !git_repo(root)? {
        return Ok(vec![]);
    }
    let out = git(root, &["status", "--porcelain", "--untracked-files=all", "."])?;
    ensure!(out.status.success(), "git status: {}", String::from_utf8_lossy(&out.stderr).trim());
    Ok(String::from_utf8_lossy(&out.stdout).lines().map(|l| l.trim().to_string()).collect())
}

/// Commit the cards repo after a push. `None` when the cards dir isn't a git
/// repo or nothing changed.
fn git_commit(root: &Path, o: &Outcome) -> Result<Option<String>> {
    if !git_repo(root)? {
        return Ok(None);
    }
    let git = |args: &[&str]| git(root, args);
    let add = git(&["add", "-A", "."])?;
    ensure!(add.status.success(), "git add: {}", String::from_utf8_lossy(&add.stderr));
    if git(&["diff", "--cached", "--quiet"])?.status.success() {
        return Ok(None);
    }
    let msg = format!(
        "marki push: +{} ~{} ->{} orphaned {}",
        o.added, o.updated, o.moved, o.quarantined + o.deleted
    );
    let commit = git(&["commit", "-q", "-m", &msg])?;
    ensure!(commit.status.success(), "git commit: {}", String::from_utf8_lossy(&commit.stderr));
    Ok(Some(msg))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn safe_rel_rejects_escapes() {
        assert!(safe_rel("a/b.md").is_ok());
        for bad in ["", "/etc/passwd", "../x.md", "a/../../x.md", "./a.md"] {
            assert!(safe_rel(bad).is_err(), "{bad}");
        }
    }
}
