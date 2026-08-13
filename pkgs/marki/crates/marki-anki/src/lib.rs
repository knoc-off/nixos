//! Direct-SQLite writer for Anki collections (v18).
//!
//! This crate writes into anki-sync-server's collection in *server mode*.
//! The full write contract lives in `docs/ANKI-SCHEMA.md`; nothing here is
//! inferred -- every rule traces back to rslib.

use anyhow::{Context, Result, bail};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use std::cmp::Ordering;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub mod deck;
pub mod media;
pub mod notes;
pub mod notetype;

/// Current wall-clock time in whole seconds since the epoch. Anki stamps
/// `notes.mod` (and most `mtime_secs` columns) in seconds.
fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Current time in milliseconds. Anki uses millisecond timestamps for object
/// ids (`notetypes.id`) and for `col.scm`.
fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Generated prost types for the vendored `.proto` subset. Modules are
/// named after each proto `package`.
pub mod proto {
    pub mod generic {
        include!(concat!(env!("OUT_DIR"), "/anki.generic.rs"));
    }
    pub mod notetypes {
        include!(concat!(env!("OUT_DIR"), "/anki.notetypes.rs"));
    }
    pub mod decks {
        include!(concat!(env!("OUT_DIR"), "/anki.decks.rs"));
    }
}

/// The only collection schema version we operate on. We refuse anything
/// else rather than attempt an upgrade.
pub const COL_VER: i64 = 18;

/// Register Anki's custom `unicase` collation. Without this even
/// `SELECT count(*) FROM decks` fails, and any other case-insensitive
/// ordering would silently corrupt the `without rowid` key order of
/// `fields`, `templates`, and `tags`.
fn register_unicase(db: &Connection) -> Result<()> {
    db.create_collation("unicase", |a: &str, b: &str| -> Ordering {
        unicase::UniCase::new(a).cmp(&unicase::UniCase::new(b))
    })
    .context("register unicase collation")?;
    Ok(())
}

/// An open Anki collection, guarded to v18 with the `unicase` collation
/// registered.
pub struct Collection {
    db: Connection,
}

impl Collection {
    /// Open a collection file, register the collation, and verify it is a
    /// v18 collection. Does not begin a transaction.
    ///
    /// Refuses to open a path that doesn't already exist rather than
    /// silently creating an empty (schema-less) SQLite file -- marki never
    /// creates a collection from scratch; Anki does that on first launch.
    pub fn open(path: &Path) -> Result<Self> {
        if !path.exists() {
            bail!(
                "no collection at {}; launch Anki once to create it, or check \
                 the `collection` path in your config",
                path.display()
            );
        }
        let db = Connection::open(path)
            .with_context(|| format!("open collection {}", path.display()))?;
        register_unicase(&db)?;

        let ver: i64 = db
            .query_row("SELECT ver FROM col", [], |r| r.get(0))
            .context("read col.ver")?;
        if ver != COL_VER {
            bail!("unsupported collection version {ver}; expected {COL_VER}");
        }

        Ok(Self { db })
    }

    /// The collection's current USN (server mode reads this from `col`).
    pub fn usn(&self) -> Result<i64> {
        let usn = self
            .db
            .query_row("SELECT usn FROM col", [], |r| r.get(0))
            .context("read col.usn")?;
        Ok(usn)
    }

    /// The collection's schema-modification time (`col.scm`).
    pub fn scm(&self) -> Result<i64> {
        let scm = self
            .db
            .query_row("SELECT scm FROM col", [], |r| r.get(0))
            .context("read col.scm")?;
        Ok(scm)
    }

    /// Write a consistent snapshot of the collection to `dest`, intended as the
    /// pre-mutation backup the write contract requires. `VACUUM INTO` produces
    /// a fully-checkpointed, standalone copy that is safe to keep even though
    /// the source is open in WAL mode -- unlike a raw file copy, which can
    /// capture a torn state. `dest` must not already exist.
    pub fn backup(&self, dest: &Path) -> Result<()> {
        if dest.exists() {
            bail!("backup destination already exists: {}", dest.display());
        }
        let dest = dest
            .to_str()
            .with_context(|| format!("backup path is not valid UTF-8: {}", dest.display()))?;
        self.db
            .execute("VACUUM INTO ?1", [dest])
            .with_context(|| format!("VACUUM INTO {dest}"))?;
        Ok(())
    }

    /// Count rows in a table (collation-sensitive tables included).
    pub fn count(&self, table: &str) -> Result<i64> {
        let sql = format!("SELECT count(*) FROM {table}");
        let n = self.db.query_row(&sql, [], |r| r.get(0)).context(sql)?;
        Ok(n)
    }

    /// Read every `notetypes.config` blob. Used to verify the vendored proto
    /// subset round-trips real collection data.
    pub fn notetype_configs(&self) -> Result<Vec<Vec<u8>>> {
        let mut stmt = self.db.prepare("SELECT config FROM notetypes ORDER BY id")?;
        let rows = stmt
            .query_map([], |r| r.get::<_, Vec<u8>>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Read every `decks.kind` blob.
    pub fn deck_kinds(&self) -> Result<Vec<Vec<u8>>> {
        let mut stmt = self.db.prepare("SELECT kind FROM decks ORDER BY id")?;
        let rows = stmt
            .query_map([], |r| r.get::<_, Vec<u8>>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Map of notetype id -> `sort_field_idx`, decoded from each notetype's
    /// config blob.
    pub fn sort_field_indices(&self) -> Result<std::collections::HashMap<i64, u32>> {
        use crate::proto::notetypes::notetype::Config;
        use prost::Message;
        let mut stmt = self.db.prepare("SELECT id, config FROM notetypes")?;
        let rows = stmt.query_map([], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, Vec<u8>>(1)?))
        })?;
        let mut out = std::collections::HashMap::new();
        for row in rows {
            let (id, blob) = row?;
            let cfg = Config::decode(blob.as_slice())
                .with_context(|| format!("decode notetype {id} config"))?;
            out.insert(id, cfg.sort_field_idx);
        }
        Ok(out)
    }

    /// Read all notes as `(mid, flds, stored_csum, stored_sfld)`.
    pub fn all_notes_raw(&self) -> Result<Vec<(i64, String, i64, String)>> {
        let mut stmt = self
            .db
            .prepare("SELECT mid, flds, csum, CAST(sfld AS text) FROM notes")?;
        let rows = stmt
            .query_map([], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Read `(id, mid, flds)` for every note, the inputs a rewrite needs.
    pub fn all_notes_for_rewrite(&self) -> Result<Vec<(i64, i64, String)>> {
        let mut stmt = self.db.prepare("SELECT id, mid, flds FROM notes")?;
        let rows = stmt
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Every note carrying `marker_tag` -- the notes marki manages. Anki stores
    /// `notes.tags` space-delimited with a leading and trailing space, so an
    /// exact whole-tag match is ` <tag> `. For each note we resolve its
    /// notetype name, split its tags, and read its cards plus the human deck
    /// name of the first card (marki keeps a note's cards in one deck). Notes
    /// with no cards report an empty deck.
    pub fn managed_notes(&self, marker_tag: &str) -> Result<Vec<RawManagedNote>> {
        let pattern = format!("% {marker_tag} %");
        let mut stmt = self.db.prepare(
            "SELECT n.id, n.guid, n.mid, nt.name, n.tags, n.flds \
             FROM notes n JOIN notetypes nt ON nt.id = n.mid \
             WHERE n.tags LIKE ?1",
        )?;
        let rows: Vec<(i64, String, i64, String, String, String)> = stmt
            .query_map([&pattern], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;

        let mut card_stmt = self.db.prepare(
            "SELECT c.id, d.name FROM cards c JOIN decks d ON d.id = c.did \
             WHERE c.nid = ?1 ORDER BY c.ord",
        )?;

        let mut out = Vec::with_capacity(rows.len());
        for (note_id, guid, mid, model_name, tags, flds) in rows {
            let cards: Vec<(i64, String)> = card_stmt
                .query_map([note_id], |r| Ok((r.get(0)?, r.get(1)?)))?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            let deck = cards
                .first()
                .map(|(_, native)| deck::native_to_human(native))
                .unwrap_or_default();
            let card_ids = cards.into_iter().map(|(id, _)| id).collect();
            out.push(RawManagedNote {
                note_id,
                guid,
                mid,
                model_name,
                tags: tags.split_whitespace().map(String::from).collect(),
                fields: notes::split_fields(&flds),
                deck,
                card_ids,
            });
        }
        Ok(out)
    }

    /// Run a batch of mutations inside a single `BEGIN EXCLUSIVE` transaction
    /// in server-USN mode. Every row written by the closure is stamped with
    /// the collection's current `usn`; `col.usn` is incremented exactly once
    /// after the batch, and only if something was actually written. On any
    /// error the transaction is rolled back and the file is untouched.
    pub fn transact<T>(
        &mut self,
        f: impl FnOnce(&mut NoteWriter) -> Result<T>,
    ) -> Result<T> {
        let usn = self.usn()?;
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Exclusive)
            .context("begin exclusive transaction")?;

        let (out, mutated, schema_changed) = {
            let mut w = NoteWriter {
                tx: &tx,
                usn,
                mutated: false,
                schema_changed: false,
            };
            let out = f(&mut w)?;
            (out, w.mutated, w.schema_changed)
        };

        if mutated {
            // increment_usn(): a single bump per sync batch, never per row.
            tx.execute("UPDATE col SET usn = usn + 1", [])
                .context("increment col.usn")?;
        }
        if schema_changed {
            // scm is only bumped when a notetype's shape changes; doing so
            // forces every client into a full re-sync, so it is never casual.
            tx.execute("UPDATE col SET scm = ?1", [now_millis()])
                .context("bump col.scm")?;
        }
        tx.commit().context("commit transaction")?;
        Ok(out)
    }
}

/// `graves.type` discriminants (`rslib` `GraveKind`): peers read these to
/// learn what kind of object was deleted.
const GRAVE_CARD: i64 = 0;
const GRAVE_NOTE: i64 = 1;

/// A note marki manages, read back from the collection for diffing. Identity
/// is the `guid`; tag interpretation (marker/hash/orphan) is the caller's
/// concern, so the raw split tags and fields are handed back as-is.
pub struct RawManagedNote {
    pub note_id: i64,
    pub guid: String,
    pub mid: i64,
    /// The notetype name, e.g. `marki:geographic-location`.
    pub model_name: String,
    /// Whitespace-split note tags (marker/hash tags included).
    pub tags: Vec<String>,
    /// Decoded field values in ord order.
    pub fields: Vec<String>,
    /// Human `::`-separated deck of the note's first card, empty if cardless.
    pub deck: String,
    pub card_ids: Vec<i64>,
}

/// Mutation handle scoped to one `transact` batch. Holds the current server
/// USN so every write is stamped consistently.
pub struct NoteWriter<'a> {
    tx: &'a rusqlite::Transaction<'a>,
    usn: i64,
    mutated: bool,
    schema_changed: bool,
}

impl NoteWriter<'_> {
    /// Pick an id not already present in `table`, starting from the current
    /// millisecond clock (Anki's object-id scheme). Ties are broken by
    /// incrementing, matching `TimestampMillis::unique`.
    fn unique_id(&self, table: &str) -> Result<i64> {
        let mut id = now_millis();
        let sql = format!("SELECT 1 FROM {table} WHERE id = ?1");
        loop {
            let taken = self
                .tx
                .query_row(&sql, [id], |_| Ok(()))
                .optional()?
                .is_some();
            if !taken {
                return Ok(id);
            }
            id += 1;
        }
    }

    /// Materialize a marki model as a notetype: insert the `notetypes` row
    /// plus one `fields` row per field and one `templates` row per card.
    /// Bumps `col.scm` (a shape change) and stamps every row with the current
    /// server USN. Returns the assigned notetype id.
    pub fn add_model(&mut self, spec: &notetype::ModelSpec) -> Result<i64> {
        use prost::Message;

        let ntid = self.unique_id("notetypes")?;
        let built = notetype::build(spec, ntid);
        let mtime = now_secs();
        let usn = self.usn;

        self.tx
            .execute(
                "INSERT INTO notetypes (id, name, mtime_secs, usn, config) \
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![built.id, built.name, mtime, usn, built.config.encode_to_vec()],
            )
            .context("insert notetype")?;

        for (ord, name, cfg) in &built.fields {
            self.tx
                .execute(
                    "INSERT INTO fields (ntid, ord, name, config) VALUES (?1, ?2, ?3, ?4)",
                    params![built.id, ord, name, cfg.encode_to_vec()],
                )
                .with_context(|| format!("insert field {name}"))?;
        }

        for (ord, name, cfg) in &built.templates {
            self.tx
                .execute(
                    "INSERT INTO templates (ntid, ord, name, mtime_secs, usn, config) \
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![built.id, ord, name, mtime, usn, cfg.encode_to_vec()],
                )
                .with_context(|| format!("insert template {name}"))?;
        }

        self.mutated = true;
        self.schema_changed = true;
        Ok(built.id)
    }

    /// Resolve a human `::`-separated deck name to its id, creating the deck
    /// and any missing ancestors. Deck creation is ordinary synced data, so
    /// it stamps `usn` but never bumps `col.scm`. Case-insensitive matching
    /// (the `name` column's `unicase` collation) means `Geography` and
    /// `geography` resolve to the same deck, matching Anki.
    pub fn deck_id_for(&mut self, human_name: &str) -> Result<i64> {
        let native = deck::human_to_native(human_name);
        self.ensure_deck_native(&native)
    }

    fn ensure_deck_native(&mut self, native: &str) -> Result<i64> {
        // Parents must exist first, or the child is orphaned in the browser.
        if let Some(parent) = deck::immediate_parent(native) {
            self.ensure_deck_native(parent)?;
        }
        if let Some(id) = self.deck_id_by_native(native)? {
            return Ok(id);
        }

        use prost::Message;
        let id = self.unique_id("decks")?;
        self.tx
            .execute(
                "INSERT INTO decks (id, name, mtime_secs, usn, common, kind) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    id,
                    native,
                    now_secs(),
                    self.usn,
                    deck::common().encode_to_vec(),
                    deck::normal_kind(deck::DEFAULT_CONFIG_ID).encode_to_vec(),
                ],
            )
            .with_context(|| format!("insert deck {native:?}"))?;
        self.mutated = true;
        Ok(id)
    }

    fn deck_id_by_native(&self, native: &str) -> Result<Option<i64>> {
        Ok(self
            .tx
            .query_row("SELECT id FROM decks WHERE name = ?1", [native], |r| r.get(0))
            .optional()?)
    }

    /// The card requirements of a notetype: `(card_ord, kind, field_ords)`
    /// per template, decoded from the stored config. Card generation uses
    /// these to decide which cards a note actually produces.
    fn notetype_reqs(&self, mid: i64) -> Result<Vec<(u32, i32, Vec<u32>)>> {
        use crate::proto::notetypes::notetype::Config;
        use prost::Message;
        let blob: Vec<u8> = self
            .tx
            .query_row("SELECT config FROM notetypes WHERE id = ?1", [mid], |r| r.get(0))
            .with_context(|| format!("load notetype {mid} config"))?;
        let cfg = Config::decode(blob.as_slice()).context("decode notetype config")?;
        Ok(cfg
            .reqs
            .into_iter()
            .map(|r| (r.card_ord, r.kind, r.field_ords))
            .collect())
    }

    /// The next new-card position (`config` key `nextPos`), defaulting to 0.
    fn next_position(&self) -> Result<i64> {
        let raw: Option<Vec<u8>> = self
            .tx
            .query_row("SELECT val FROM config WHERE key = 'nextPos'", [], |r| r.get(0))
            .optional()?;
        match raw {
            Some(bytes) => {
                let s = std::str::from_utf8(&bytes).unwrap_or("0").trim();
                Ok(s.parse().unwrap_or(0))
            }
            None => Ok(0),
        }
    }

    /// Persist an advanced `nextPos`, stamping usn/mtime like any config row.
    fn set_next_position(&self, pos: i64) -> Result<()> {
        self.tx
            .execute(
                "INSERT INTO config (key, usn, mtime_secs, val) VALUES ('nextPos', ?1, ?2, ?3) \
                 ON CONFLICT(key) DO UPDATE SET usn=?1, mtime_secs=?2, val=?3",
                params![self.usn, now_secs(), pos.to_string().into_bytes()],
            )
            .context("update nextPos")?;
        Ok(())
    }

    /// Register a tag so the `tags` table stays consistent with note tags.
    fn register_tag(&self, tag: &str) -> Result<()> {
        self.tx
            .execute(
                "INSERT INTO tags (tag, usn, collapsed, config) VALUES (?1, ?2, 0, NULL) \
                 ON CONFLICT(tag) DO NOTHING",
                params![tag, self.usn],
            )
            .with_context(|| format!("register tag {tag:?}"))?;
        Ok(())
    }

    /// Create a note and generate its cards. Fields are normalized and encoded
    /// exactly as [`rewrite_note_fields`](Self::rewrite_note_fields); tags are
    /// canonicalized and registered; then one card is generated per satisfied
    /// requirement, all sharing the note's new-card position (`nextPos`, bumped
    /// once for the note). `guid` is the caller-supplied stable identity.
    pub fn add_note(
        &mut self,
        mid: i64,
        guid: &str,
        fields: Vec<String>,
        sort_field_idx: u32,
        tags: &[String],
        deck_id: i64,
    ) -> Result<i64> {
        let (norm, csum, sfld) = notes::prepare_fields(fields, sort_field_idx, true);
        let flds = notes::join_fields(&norm);
        let tag_str = notes::canonical_tags(tags);

        let nid = self.unique_id("notes")?;
        self.tx
            .execute(
                "INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, '')",
                params![nid, guid, mid, now_secs(), self.usn, tag_str, flds, sfld, csum as i64],
            )
            .with_context(|| format!("insert note {guid}"))?;

        for tag in tags.iter().map(|t| t.trim()).filter(|t| !t.is_empty()) {
            self.register_tag(tag)?;
        }

        // Generate cards. A requirement is satisfied when the referenced
        // fields are non-empty (ANY: at least one; ALL: all); NONE never
        // generates. Empty is whitespace-only, matching Anki.
        let reqs = self.notetype_reqs(mid)?;
        let pos = self.next_position()?;
        let nonempty = |ord: u32| {
            norm.get(ord as usize)
                .map(|f| !f.trim().is_empty())
                .unwrap_or(false)
        };
        let mut generated = 0;
        for (card_ord, kind, field_ords) in reqs {
            let satisfied = match kind {
                1 => field_ords.iter().any(|&o| nonempty(o)), // ANY
                2 => !field_ords.is_empty() && field_ords.iter().all(|&o| nonempty(o)), // ALL
                _ => false,                                   // NONE / unknown
            };
            if !satisfied {
                continue;
            }
            self.insert_card(nid, deck_id, card_ord, pos)?;
            generated += 1;
        }
        if generated > 0 {
            self.set_next_position(pos + 1)?;
        }

        self.mutated = true;
        Ok(nid)
    }

    /// Insert a fresh, unseen card at new-card position `pos` with zeroed
    /// scheduling. Shared by note creation and card (re)generation.
    fn insert_card(&self, nid: i64, did: i64, card_ord: u32, pos: i64) -> Result<()> {
        let cid = self.unique_id("cards")?;
        self.tx
            .execute(
                "INSERT INTO cards \
                 (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, \
                  reps, lapses, left, odue, odid, flags, data) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0, 0, ?7, 0, 0, 0, 0, 0, 0, 0, 0, '{}')",
                params![cid, nid, did, card_ord, now_secs(), self.usn, pos],
            )
            .with_context(|| format!("insert card ord {card_ord} for note {nid}"))?;
        Ok(())
    }

    /// Re-encode an existing note's fields and write them back: normalize,
    /// derive `csum`/`sfld`, join with `0x1f`, bump `mod`, and stamp `usn`.
    /// Scheduling columns and cards are deliberately left untouched -- a field
    /// edit never changes review history.
    ///
    /// `sfld` is bound as text; the column's integer affinity makes SQLite
    /// store a pure-number sort field numerically, exactly as Anki does.
    pub fn rewrite_note_fields(
        &mut self,
        note_id: i64,
        fields: Vec<String>,
        sort_field_idx: u32,
    ) -> Result<()> {
        let (norm, csum, sfld) = notes::prepare_fields(fields, sort_field_idx, true);
        let flds = notes::join_fields(&norm);
        self.tx
            .execute(
                "UPDATE notes SET mod=?1, usn=?2, flds=?3, sfld=?4, csum=?5 WHERE id=?6",
                params![now_secs(), self.usn, flds, sfld, csum as i64, note_id],
            )
            .with_context(|| format!("update note {note_id}"))?;
        self.mutated = true;
        Ok(())
    }

    /// Update an existing note's fields *and* tags in one shot (used when a
    /// note's content or tag set changed on disk). Fields are encoded exactly
    /// as [`add_note`](Self::add_note); tags are canonicalized and registered.
    /// Cards and scheduling columns are left untouched -- content edits never
    /// touch review history. If tags gained or lost a card-affecting field the
    /// caller regenerates cards separately.
    pub fn update_note(
        &mut self,
        note_id: i64,
        fields: Vec<String>,
        sort_field_idx: u32,
        tags: &[String],
    ) -> Result<()> {
        let (norm, csum, sfld) = notes::prepare_fields(fields, sort_field_idx, true);
        let flds = notes::join_fields(&norm);
        let tag_str = notes::canonical_tags(tags);
        self.tx
            .execute(
                "UPDATE notes SET mod=?1, usn=?2, tags=?3, flds=?4, sfld=?5, csum=?6 WHERE id=?7",
                params![now_secs(), self.usn, tag_str, flds, sfld, csum as i64, note_id],
            )
            .with_context(|| format!("update note {note_id}"))?;
        for tag in tags.iter().map(|t| t.trim()).filter(|t| !t.is_empty()) {
            self.register_tag(tag)?;
        }
        self.mutated = true;
        Ok(())
    }

    /// Move every card of a note into `deck_id`. Deck membership is not a
    /// scheduling column, so this preserves review history; only `did` (plus
    /// the housekeeping `usn`/`mod`) changes.
    pub fn set_note_deck(&mut self, note_id: i64, deck_id: i64) -> Result<()> {
        let n = self
            .tx
            .execute(
                "UPDATE cards SET did=?1, usn=?2, mod=?3 WHERE nid=?4",
                params![deck_id, self.usn, now_secs(), note_id],
            )
            .with_context(|| format!("move note {note_id} to deck {deck_id}"))?;
        if n > 0 {
            self.mutated = true;
        }
        Ok(())
    }

    /// Suspend every active card of a note (`queue = -1`), the quarantine used
    /// for a soft-deleted orphan. Scheduling history is retained -- suspension
    /// only removes cards from review. Already-suspended/buried cards
    /// (`queue < 0`) are left alone. Returns the number of cards suspended.
    pub fn suspend_note_cards(&mut self, note_id: i64) -> Result<usize> {
        let n = self
            .tx
            .execute(
                "UPDATE cards SET queue=-1, usn=?1, mod=?2 WHERE nid=?3 AND queue >= 0",
                params![self.usn, now_secs(), note_id],
            )
            .with_context(|| format!("suspend cards of note {note_id}"))?;
        if n > 0 {
            self.mutated = true;
        }
        Ok(n)
    }

    /// Add a single tag to a note if absent, rewriting the tag string in
    /// canonical (sorted, space-wrapped) form and registering it. Used to mark
    /// a quarantined orphan.
    pub fn add_tag_to_note(&mut self, note_id: i64, tag: &str) -> Result<()> {
        let current: String = self
            .tx
            .query_row("SELECT tags FROM notes WHERE id = ?1", [note_id], |r| r.get(0))
            .with_context(|| format!("read tags of note {note_id}"))?;
        let mut list: Vec<String> = current.split_whitespace().map(String::from).collect();
        if list.iter().any(|t| t == tag) {
            return Ok(());
        }
        list.push(tag.to_string());
        let canon = notes::canonical_tags(&list);
        self.tx
            .execute(
                "UPDATE notes SET tags=?1, usn=?2, mod=?3 WHERE id=?4",
                params![canon, self.usn, now_secs(), note_id],
            )
            .with_context(|| format!("add tag {tag:?} to note {note_id}"))?;
        self.register_tag(tag)?;
        self.mutated = true;
        Ok(())
    }

    /// The notetype id for a name (e.g. `marki:basic`), if it exists.
    pub fn notetype_id_by_name(&self, name: &str) -> Result<Option<i64>> {
        Ok(self
            .tx
            .query_row("SELECT id FROM notetypes WHERE name = ?1", [name], |r| r.get(0))
            .optional()?)
    }

    /// Template names of a notetype in ord order -- the committed card
    /// ordering that the append-only rule is checked against.
    fn template_names(&self, ntid: i64) -> Result<Vec<String>> {
        let mut stmt = self
            .tx
            .prepare("SELECT name FROM templates WHERE ntid = ?1 ORDER BY ord")?;
        let rows = stmt
            .query_map([ntid], |r| r.get::<_, String>(0))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    }

    /// Ensure a notetype matching `spec` exists, and return its id. This is the
    /// database-derived replacement for the old `model_state.json`: the
    /// committed template ordering lives in the `templates` table, and the
    /// append-only rule is enforced against it.
    ///
    /// - New notetype -> create it (a shape change, bumps `col.scm`).
    /// - Unchanged shape and css -> reuse as-is, no writes.
    /// - Appended card names (existing names are a prefix of `spec.card_names`)
    ///   -> add the new field/template rows, rewrite the config (new reqs/css),
    ///   bump `col.scm`, and generate the new cards for existing notes.
    /// - Only the css changed -> rewrite the config, no `scm` bump.
    /// - Reordered or removed templates -> refuse (would corrupt reviews).
    pub fn ensure_model(&mut self, spec: &notetype::ModelSpec) -> Result<i64> {
        use prost::Message;

        let name = spec.notetype_name();
        let Some(ntid) = self.notetype_id_by_name(&name)? else {
            return self.add_model(spec);
        };

        let existing = self.template_names(ntid)?;
        let want = &spec.card_names;
        let is_append = want.len() >= existing.len() && want[..existing.len()] == existing[..];
        if !is_append {
            bail!(
                "model {name:?}: templates reordered or removed (have {existing:?}, want {want:?}); \
                 refusing to rewrite -- this would corrupt existing reviews"
            );
        }

        let built = notetype::build(spec, ntid);
        let shape_changed = want.len() > existing.len();

        // Read the current css to decide whether a same-shape update is needed.
        let cur_blob: Vec<u8> = self
            .tx
            .query_row("SELECT config FROM notetypes WHERE id = ?1", [ntid], |r| r.get(0))
            .with_context(|| format!("load notetype {ntid} config"))?;
        let cur_css = crate::proto::notetypes::notetype::Config::decode(cur_blob.as_slice())
            .map(|c| c.css)
            .unwrap_or_default();
        if !shape_changed && cur_css == spec.css {
            return Ok(ntid); // fully up to date
        }

        let mtime = now_secs();
        // Insert the newly-appended fields (2 per new card) and templates.
        let old_field_count = existing.len() * 2;
        for (ord, fname, fcfg) in built.fields.iter().skip(old_field_count) {
            self.tx
                .execute(
                    "INSERT INTO fields (ntid, ord, name, config) VALUES (?1, ?2, ?3, ?4)",
                    params![ntid, ord, fname, fcfg.encode_to_vec()],
                )
                .with_context(|| format!("append field {fname}"))?;
        }
        for (ord, tname, tcfg) in built.templates.iter().skip(existing.len()) {
            self.tx
                .execute(
                    "INSERT INTO templates (ntid, ord, name, mtime_secs, usn, config) \
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![ntid, ord, tname, mtime, self.usn, tcfg.encode_to_vec()],
                )
                .with_context(|| format!("append template {tname}"))?;
        }
        // Rewrite the notetype config: new reqs (for appends) and/or css.
        self.tx
            .execute(
                "UPDATE notetypes SET config=?1, mtime_secs=?2, usn=?3 WHERE id=?4",
                params![built.config.encode_to_vec(), mtime, self.usn, ntid],
            )
            .with_context(|| format!("update notetype {ntid} config"))?;

        self.mutated = true;
        if shape_changed {
            self.schema_changed = true;
            self.pad_notes_to_field_count(ntid, built.fields.len())?;
            self.generate_missing_cards(ntid)?;
        }
        Ok(ntid)
    }

    /// Pad every note of a notetype whose `flds` has fewer than `count` fields
    /// with empty trailing fields. Required after appending fields to a model:
    /// Anki's Check Database flags any note whose field count does not match its
    /// notetype. `csum`/`sfld` derive from field 0 (or the sort field, which
    /// marki fixes at 0), so appending empty tail fields leaves them unchanged.
    fn pad_notes_to_field_count(&mut self, mid: i64, count: usize) -> Result<()> {
        let notes: Vec<(i64, String)> = {
            let mut stmt = self.tx.prepare("SELECT id, flds FROM notes WHERE mid = ?1")?;
            stmt.query_map([mid], |r| Ok((r.get(0)?, r.get(1)?)))?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for (nid, flds) in notes {
            let mut fields = notes::split_fields(&flds);
            if fields.len() >= count {
                continue;
            }
            fields.resize(count, String::new());
            let joined = notes::join_fields(&fields);
            self.tx
                .execute(
                    "UPDATE notes SET flds=?1, mod=?2, usn=?3 WHERE id=?4",
                    params![joined, now_secs(), self.usn, nid],
                )
                .with_context(|| format!("pad note {nid} to {count} fields"))?;
        }
        Ok(())
    }

    /// Generate any cards a notetype's `reqs` call for but that don't yet exist
    /// on its notes. Used after appending templates to a model so pre-existing
    /// notes gain the new card(s). Idempotent: only missing `(nid, ord)` pairs
    /// are inserted, and only where the requirement is satisfied.
    fn generate_missing_cards(&mut self, mid: i64) -> Result<usize> {
        let reqs = self.notetype_reqs(mid)?;
        let notes: Vec<(i64, String)> = {
            let mut stmt = self
                .tx
                .prepare("SELECT id, flds FROM notes WHERE mid = ?1")?;
            stmt.query_map([mid], |r| Ok((r.get(0)?, r.get(1)?)))?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };

        let mut generated = 0;
        for (nid, flds) in notes {
            let fields = notes::split_fields(&flds);
            let nonempty = |ord: u32| {
                fields
                    .get(ord as usize)
                    .map(|f| !f.trim().is_empty())
                    .unwrap_or(false)
            };
            // A new card inherits the note's deck (its existing cards' did),
            // falling back to the default deck when the note has none yet.
            let did: i64 = self
                .tx
                .query_row(
                    "SELECT did FROM cards WHERE nid = ?1 ORDER BY ord LIMIT 1",
                    [nid],
                    |r| r.get(0),
                )
                .optional()?
                .unwrap_or(1);
            for (card_ord, kind, field_ords) in &reqs {
                let exists = self
                    .tx
                    .query_row(
                        "SELECT 1 FROM cards WHERE nid = ?1 AND ord = ?2",
                        params![nid, card_ord],
                        |_| Ok(()),
                    )
                    .optional()?
                    .is_some();
                if exists {
                    continue;
                }
                let satisfied = match kind {
                    1 => field_ords.iter().any(|&o| nonempty(o)),
                    2 => !field_ords.is_empty() && field_ords.iter().all(|&o| nonempty(o)),
                    _ => false,
                };
                if !satisfied {
                    continue;
                }
                let pos = self.next_position()?;
                self.insert_card(nid, did, *card_ord, pos)?;
                self.set_next_position(pos + 1)?;
                generated += 1;
            }
        }
        if generated > 0 {
            self.mutated = true;
        }
        Ok(generated)
    }

    /// Record a grave so peers learn an object was deleted. `OR IGNORE` on the
    /// `(oid, type)` primary key makes a repeated delete idempotent (a second
    /// grave for the same object is silently dropped), mirroring rslib's
    /// `add.sql`.
    fn add_grave(&self, oid: i64, kind: i64) -> Result<()> {
        self.tx
            .execute(
                "INSERT OR IGNORE INTO graves (usn, oid, type) VALUES (?1, ?2, ?3)",
                params![self.usn, oid, kind],
            )
            .with_context(|| format!("insert grave oid={oid} type={kind}"))?;
        Ok(())
    }

    /// Delete a note and all its cards, recording a grave for each so the
    /// deletion propagates on sync instead of the note reappearing from a
    /// peer. Mirrors rslib `remove_notes_inner`: for every card add a card
    /// grave then remove the card row, then remove the note row and add a note
    /// grave (the card/note order asymmetry is rslib's). `revlog` and `tags`
    /// are deliberately left untouched -- review history survives a note
    /// deletion, and tag GC is a separate concern. Idempotent: deleting an
    /// already-absent note is a no-op. Returns the number of cards removed.
    pub fn remove_note(&mut self, note_id: i64) -> Result<usize> {
        let exists = self
            .tx
            .query_row("SELECT 1 FROM notes WHERE id = ?1", [note_id], |_| Ok(()))
            .optional()?
            .is_some();
        if !exists {
            return Ok(0);
        }

        let card_ids: Vec<i64> = {
            let mut stmt = self.tx.prepare("SELECT id FROM cards WHERE nid = ?1")?;
            stmt.query_map([note_id], |r| r.get(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?
        };
        for cid in &card_ids {
            self.add_grave(*cid, GRAVE_CARD)?;
            self.tx
                .execute("DELETE FROM cards WHERE id = ?1", [cid])
                .with_context(|| format!("delete card {cid}"))?;
        }

        self.tx
            .execute("DELETE FROM notes WHERE id = ?1", [note_id])
            .with_context(|| format!("delete note {note_id}"))?;
        self.add_grave(note_id, GRAVE_NOTE)?;

        self.mutated = true;
        Ok(card_ids.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Path to a disposable copy of the real fixture. Skips the test if the
    /// copy is absent so the suite still runs in a clean checkout.
    fn fixture() -> Option<std::path::PathBuf> {
        let p = dirs_home()?.join("projects/scratch/collection.copy.anki2");
        p.exists().then_some(p)
    }

    fn dirs_home() -> Option<std::path::PathBuf> {
        std::env::var_os("HOME").map(std::path::PathBuf::from)
    }

    #[test]
    fn opens_fixture_and_reads_guarded_version() {
        let Some(path) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let col = Collection::open(&path).unwrap();
        assert_eq!(col.usn().unwrap(), 257);
        // These three tables all declare COLLATE unicase columns; counting
        // them proves the collation is registered.
        assert_eq!(col.count("notes").unwrap(), 323);
        assert_eq!(col.count("decks").unwrap() > 0, true);
        assert_eq!(col.count("tags").unwrap() > 0, true);
    }

    #[test]
    fn notetype_config_blobs_round_trip_byte_for_byte() {
        use crate::proto::notetypes::notetype::Config;
        use prost::Message;

        let Some(path) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let col = Collection::open(&path).unwrap();
        let blobs = col.notetype_configs().unwrap();
        assert_eq!(blobs.len(), 9, "fixture has 9 notetypes");

        // Decoding then re-encoding every real config blob must reproduce the
        // exact bytes. If our vendored subset dropped a field that a real
        // notetype uses, prost round-trips it through the `other`/unknown
        // path or drops it -- either way the bytes would differ and this
        // fails, which is the whole point of the check.
        for (i, blob) in blobs.iter().enumerate() {
            let msg = Config::decode(blob.as_slice())
                .unwrap_or_else(|e| panic!("decode notetype config {i}: {e}"));
            let re = msg.encode_to_vec();
            assert_eq!(&re, blob, "notetype config {i} did not round-trip");
        }
    }

    #[test]
    fn deck_kind_blobs_round_trip_byte_for_byte() {
        use crate::proto::decks::deck::KindContainer;
        use prost::Message;

        let Some(path) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let col = Collection::open(&path).unwrap();
        for (i, blob) in col.deck_kinds().unwrap().iter().enumerate() {
            let msg = KindContainer::decode(blob.as_slice())
                .unwrap_or_else(|e| panic!("decode deck kind {i}: {e}"));
            let re = msg.encode_to_vec();
            assert_eq!(&re, blob, "deck kind {i} did not round-trip");
        }
    }

    #[test]
    fn note_csum_and_sfld_match_anki_for_every_fixture_note() {
        let Some(path) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let col = Collection::open(&path).unwrap();
        let sort_idx = col.sort_field_indices().unwrap();
        let notes = col.all_notes_raw().unwrap();
        assert_eq!(notes.len(), 323, "fixture note count");

        // Recompute csum + sfld from flds exactly as rslib does, and require
        // they match what Anki itself stored. Matching all 323 real notes is
        // the correctness proof for the note encoder: these stored values are
        // authoritative Anki output.
        let mut checked = 0;
        for (mid, flds, stored_csum, stored_sfld) in &notes {
            let idx = *sort_idx.get(mid).expect("notetype for note");
            let fields = crate::notes::split_fields(flds);
            let (_norm, csum, sfld) =
                crate::notes::prepare_fields(fields, idx, true);
            // Stored csum is an i64 holding a u32 bit pattern.
            assert_eq!(
                csum as i64, *stored_csum,
                "csum mismatch for note mid={mid}"
            );
            assert_eq!(&sfld, stored_sfld, "sfld mismatch for note mid={mid}");
            checked += 1;
        }
        assert_eq!(checked, 323);
    }

    #[test]
    fn rewrite_all_notes_through_writer_produces_checkdb_clean_copy() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        // Work on a distinct file so the gate harness (run separately) has a
        // stable path, and the pristine copy is never mutated.
        let out = src.with_file_name("collection.rewrite.anki2");
        std::fs::copy(&src, &out).unwrap();

        let before_usn;
        {
            let mut col = Collection::open(&out).unwrap();
            before_usn = col.usn().unwrap();
            let sort_idx = col.sort_field_indices().unwrap();
            let rows = col.all_notes_for_rewrite().unwrap();
            assert_eq!(rows.len(), 323);

            // Rewrite every note with its own current fields. Output must be
            // byte-identical in meaning (csum/sfld) but freshly encoded by our
            // writer -- the point is to prove our encode+txn+USN path yields a
            // collection real Anki's Check Database accepts.
            col.transact(|w| {
                for (id, mid, flds) in &rows {
                    let idx = *sort_idx.get(mid).expect("notetype for note");
                    let fields = crate::notes::split_fields(flds);
                    w.rewrite_note_fields(*id, fields, idx)?;
                }
                Ok(())
            })
            .unwrap();
        }

        // Server-mode USN: incremented exactly once for the whole batch.
        let col = Collection::open(&out).unwrap();
        assert_eq!(col.usn().unwrap(), before_usn + 1);
        // Every note row now carries the pre-batch USN we stamped.
        let stamped: i64 = col
            .db
            .query_row("SELECT count(*) FROM notes WHERE usn = ?1", [before_usn], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(stamped, 323);

        // csum/sfld still match Anki's authoritative values after the rewrite.
        let sort_idx = col.sort_field_indices().unwrap();
        for (mid, flds, stored_csum, stored_sfld) in col.all_notes_raw().unwrap() {
            let idx = *sort_idx.get(&mid).unwrap();
            let (_n, csum, sfld) =
                crate::notes::prepare_fields(crate::notes::split_fields(&flds), idx, true);
            assert_eq!(csum as i64, stored_csum);
            assert_eq!(sfld, stored_sfld);
        }
        // Left at `out` for `anki-checkdb.sh` to validate against real Anki.
    }

    #[test]
    fn add_model_creates_checkdb_clean_notetype() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.newmodel.anki2");
        std::fs::copy(&src, &out).unwrap();

        let spec = notetype::ModelSpec {
            // Distinct name so it cannot collide with the fixture's existing
            // marki:geographic-location notetype.
            name: "capital-city".into(),
            css: ".card { text-align: center; }".into(),
            card_names: vec!["Locate".into(), "Identify".into()],
        };

        let (ntid, scm_before, scm_after);
        {
            let mut col = Collection::open(&out).unwrap();
            scm_before = col.scm().unwrap();
            ntid = col.transact(|w| w.add_model(&spec)).unwrap();
            scm_after = Collection::open(&out).unwrap().scm().unwrap();
        }

        // A shape change must bump scm.
        assert!(scm_after > scm_before, "scm must advance on notetype add");

        let col = Collection::open(&out).unwrap();
        // notetype + 4 fields + 2 templates present with the expected shape.
        let name: String = col
            .db
            .query_row("SELECT name FROM notetypes WHERE id=?1", [ntid], |r| r.get(0))
            .unwrap();
        assert_eq!(name, "marki:capital-city");
        let nfields: i64 = col
            .db
            .query_row("SELECT count(*) FROM fields WHERE ntid=?1", [ntid], |r| r.get(0))
            .unwrap();
        let ntemplates: i64 = col
            .db
            .query_row("SELECT count(*) FROM templates WHERE ntid=?1", [ntid], |r| r.get(0))
            .unwrap();
        assert_eq!((nfields, ntemplates), (4, 2));
        // Config blob round-trips, proving we wrote a well-formed message.
        let blob: Vec<u8> = col
            .db
            .query_row("SELECT config FROM notetypes WHERE id=?1", [ntid], |r| r.get(0))
            .unwrap();
        use crate::proto::notetypes::notetype::Config;
        use prost::Message;
        assert!(Config::decode(blob.as_slice()).is_ok());
        // Left at `out` for the Check Database gate.
    }

    #[test]
    fn create_nested_decks_creates_ancestors_and_is_checkdb_clean() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.decks.anki2");
        std::fs::copy(&src, &out).unwrap();

        let (france_id, scm_before, scm_after, usn_before);
        {
            let mut col = Collection::open(&out).unwrap();
            scm_before = col.scm().unwrap();
            usn_before = col.usn().unwrap();
            // A path that does not yet exist in the fixture, exercising the
            // full ancestor chain and the blank-component rule mid-path.
            france_id = col
                .transact(|w| {
                    let a = w.deck_id_for("programming::rust::ownership")?;
                    // Idempotent: asking again returns the same id, no dup row.
                    let b = w.deck_id_for("programming::rust::ownership")?;
                    assert_eq!(a, b);
                    // Blank component becomes "blank".
                    w.deck_id_for("programming::::edge")?;
                    Ok(a)
                })
                .unwrap();
            scm_after = Collection::open(&out).unwrap().scm().unwrap();
        }

        let col = Collection::open(&out).unwrap();
        // Deck creation is normal data: usn advances, scm does NOT.
        assert_eq!(scm_after, scm_before, "deck creation must not bump scm");
        assert_eq!(col.usn().unwrap(), usn_before + 1);

        // Every ancestor exists as its own native-named row.
        for native in [
            "programming\u{1f}rust\u{1f}ownership",
            "programming\u{1f}rust",
            "programming\u{1f}blank\u{1f}edge",
        ] {
            let n: i64 = col
                .db
                .query_row("SELECT count(*) FROM decks WHERE name=?1", [native], |r| r.get(0))
                .unwrap();
            assert_eq!(n, 1, "expected exactly one deck named {native:?}");
        }
        // No duplicate rows from the repeated call.
        let france_rows: i64 = col
            .db
            .query_row("SELECT count(*) FROM decks WHERE id=?1", [france_id], |r| r.get(0))
            .unwrap();
        assert_eq!(france_rows, 1);
        // Left at `out` for the Check Database gate.
    }

    #[test]
    fn end_to_end_build_from_scratch_is_checkdb_clean() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.scratch.anki2");
        std::fs::copy(&src, &out).unwrap();

        let spec = notetype::ModelSpec {
            name: "capital-city".into(),
            css: ".card { text-align: center; }".into(),
            card_names: vec!["Locate".into(), "Identify".into(), "Flag".into()],
        };

        let (nid, full_cards, partial_cards);
        {
            let mut col = Collection::open(&out).unwrap();
            (nid, full_cards, partial_cards) = col
                .transact(|w| {
                    let mid = w.add_model(&spec)?;
                    let did = w.deck_id_for("geography::europe::france")?;

                    // A note with every field populated -> all 3 cards.
                    let guid_a = notes::anki_base91(0x1234_5678_9abc_def0);
                    let a = w.add_note(
                        mid,
                        &guid_a,
                        vec![
                            "Where is France?".into(),
                            "Western Europe".into(),
                            "Name this country".into(),
                            "France".into(),
                            "Whose flag?".into(),
                            "France".into(),
                        ],
                        0,
                        &["geography".into(), "europe".into()],
                        did,
                    )?;
                    let a_cards: i64 = w
                        .tx
                        .query_row("SELECT count(*) FROM cards WHERE nid=?1", [a], |r| r.get(0))?;

                    // A note whose Flag front (ord 4) is empty -> only 2 cards
                    // (the ANY req on ord 4 is unsatisfied).
                    let guid_b = notes::anki_base91(0x0fed_cba9_8765_4321);
                    let b = w.add_note(
                        mid,
                        &guid_b,
                        vec![
                            "Where is Spain?".into(),
                            "Iberia".into(),
                            "Name this country".into(),
                            "Spain".into(),
                            String::new(),
                            String::new(),
                        ],
                        0,
                        &["geography".into()],
                        did,
                    )?;
                    let b_cards: i64 = w
                        .tx
                        .query_row("SELECT count(*) FROM cards WHERE nid=?1", [b], |r| r.get(0))?;

                    Ok((a, a_cards, b_cards))
                })
                .unwrap();
        }

        // Card generation honored reqs: full note -> 3 cards, partial -> 2.
        assert_eq!(full_cards, 3, "fully-populated note generates all cards");
        assert_eq!(partial_cards, 2, "empty front field suppresses its card");

        let col = Collection::open(&out).unwrap();
        // The note's cards all landed in the resolved native deck.
        let did: i64 = col
            .db
            .query_row(
                "SELECT id FROM decks WHERE name = ?1",
                ["geography\u{1f}europe\u{1f}france"],
                |r| r.get(0),
            )
            .unwrap();
        let in_deck: i64 = col
            .db
            .query_row("SELECT count(*) FROM cards WHERE nid=?1 AND did=?2", params![nid, did], |r| {
                r.get(0)
            })
            .unwrap();
        assert_eq!(in_deck, 3);
        // Left at `out` for the Check Database gate.
    }

    #[test]
    fn managed_notes_reads_marker_tagged_notes() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        // The fixture tags all 323 of its notes with `marki`.
        let col = Collection::open(&src).unwrap();
        let managed = col.managed_notes("marki").unwrap();
        assert_eq!(managed.len(), 323);
        assert!(managed.iter().all(|m| !m.guid.is_empty()));
        assert!(managed.iter().all(|m| !m.model_name.is_empty()));
        assert!(managed.iter().any(|m| !m.deck.is_empty()));
        assert!(managed.iter().all(|m| m.tags.iter().any(|t| t == "marki")));
    }

    #[test]
    fn ensure_model_create_append_and_write_apis_are_checkdb_clean() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.phase6.anki2");
        std::fs::copy(&src, &out).unwrap();

        let (nid, cards_after_append, moved_did, suspended);
        {
            let mut col = Collection::open(&out).unwrap();
            (nid, cards_after_append, moved_did, suspended) = col
                .transact(|w| {
                    let spec1 = notetype::ModelSpec {
                        name: "phase6".into(),
                        css: ".card{}".into(),
                        card_names: vec!["Card".into()],
                    };
                    let mid = w.ensure_model(&spec1)?;
                    // Re-running with identical spec is a no-op reuse.
                    assert_eq!(w.ensure_model(&spec1)?, mid);

                    let did = w.deck_id_for("phase6::start")?;
                    let guid = notes::anki_base91(0x00c0_ffee_0000_0001);
                    let nid = w.add_note(
                        mid,
                        &guid,
                        vec!["Front side".into(), "Back side".into()],
                        0,
                        &["phase6".into(), "marki".into(), "marki::hash:aaaa".into()],
                        did,
                    )?;
                    let c0: i64 = w.tx.query_row(
                        "SELECT count(*) FROM cards WHERE nid=?1",
                        [nid],
                        |r| r.get(0),
                    )?;
                    assert_eq!(c0, 1, "single-card model generates one card");

                    // Content + tag update: fields and tags change, card stays.
                    w.update_note(
                        nid,
                        vec!["Front v2".into(), "Back v2".into()],
                        0,
                        &["phase6".into(), "marki".into(), "marki::hash:bbbb".into()],
                    )?;

                    // Move the note to another deck.
                    let dest = w.deck_id_for("phase6::moved")?;
                    w.set_note_deck(nid, dest)?;

                    // Append a second card. The existing note is padded to 4
                    // fields so Check Database stays happy.
                    let spec2 = notetype::ModelSpec {
                        name: "phase6".into(),
                        css: ".card{}".into(),
                        card_names: vec!["Card".into(), "Reverse".into()],
                    };
                    assert_eq!(w.ensure_model(&spec2)?, mid);
                    // Fill the reverse fields, then regen: the new card appears.
                    w.update_note(
                        nid,
                        vec![
                            "Front v2".into(),
                            "Back v2".into(),
                            "Reverse front".into(),
                            "Reverse back".into(),
                        ],
                        0,
                        &["phase6".into(), "marki".into(), "marki::hash:cccc".into()],
                    )?;
                    w.generate_missing_cards(mid)?;
                    let c1: i64 = w.tx.query_row(
                        "SELECT count(*) FROM cards WHERE nid=?1",
                        [nid],
                        |r| r.get(0),
                    )?;

                    // Suspend (quarantine) and tag the note.
                    let s = w.suspend_note_cards(nid)?;
                    w.add_tag_to_note(nid, "marki::orphan")?;

                    Ok((nid, c1, dest, s))
                })
                .unwrap();
        }

        let col = Collection::open(&out).unwrap();
        assert_eq!(cards_after_append, 2, "reverse card generated after fill");
        let in_deck: i64 = col
            .db
            .query_row(
                "SELECT count(*) FROM cards WHERE nid=?1 AND did=?2",
                params![nid, moved_did],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(in_deck, 2);
        assert_eq!(suspended, 2);
        let live: i64 = col
            .db
            .query_row(
                "SELECT count(*) FROM cards WHERE nid=?1 AND queue >= 0",
                [nid],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(live, 0, "all cards suspended");
        let tags: String = col
            .db
            .query_row("SELECT tags FROM notes WHERE id=?1", [nid], |r| r.get(0))
            .unwrap();
        assert!(tags.contains("marki::orphan"));
        assert!(tags.contains("marki::hash:cccc"));
        // Left at `out` for the Check Database gate.
    }

    #[test]
    fn ensure_model_refuses_template_reorder() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.reorder.anki2");
        std::fs::copy(&src, &out).unwrap();
        let mut col = Collection::open(&out).unwrap();
        let err = col.transact(|w| {
            w.ensure_model(&notetype::ModelSpec {
                name: "reord".into(),
                css: String::new(),
                card_names: vec!["A".into(), "B".into()],
            })?;
            w.ensure_model(&notetype::ModelSpec {
                name: "reord".into(),
                css: String::new(),
                card_names: vec!["B".into(), "A".into()],
            })?;
            Ok(())
        });
        assert!(err.is_err(), "reordering templates must be rejected");
        let _ = std::fs::remove_file(&out);
    }

    #[test]
    fn backup_produces_a_standalone_openable_copy() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let work = src.with_file_name("collection.backupsrc.anki2");
        std::fs::copy(&src, &work).unwrap();
        let dest = src.with_file_name("collection.backup.anki2");
        let _ = std::fs::remove_file(&dest);

        {
            let col = Collection::open(&work).unwrap();
            col.backup(&dest).unwrap();
            // A second backup to the same path must refuse rather than clobber.
            assert!(col.backup(&dest).is_err());
        }

        // The backup is a real, independent v18 collection with the same notes.
        let backup = Collection::open(&dest).unwrap();
        assert_eq!(backup.count("notes").unwrap(), 323);
        assert_eq!(backup.usn().unwrap(), 257);
        let _ = std::fs::remove_file(&dest);
        let _ = std::fs::remove_file(&work);
    }

    #[test]
    fn remove_note_records_graves_and_is_checkdb_clean() {
        let Some(src) = fixture() else {
            eprintln!("skip: fixture copy not present");
            return;
        };
        let out = src.with_file_name("collection.graves.anki2");
        std::fs::copy(&src, &out).unwrap();

        // Pick a real note that actually has cards, so we exercise both the
        // card graves and the note grave.
        let (nid, card_count, usn_before): (i64, i64, i64);
        {
            let col = Collection::open(&out).unwrap();
            usn_before = col.usn().unwrap();
            (nid, card_count) = col
                .db
                .query_row(
                    "SELECT n.id, count(c.id) FROM notes n JOIN cards c ON c.nid = n.id \
                     GROUP BY n.id HAVING count(c.id) > 0 LIMIT 1",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?)),
                )
                .unwrap();
        }

        let removed;
        {
            let mut col = Collection::open(&out).unwrap();
            removed = col
                .transact(|w| {
                    let n = w.remove_note(nid)?;
                    // Idempotent: a second delete of the same note is a no-op
                    // and adds no further graves.
                    assert_eq!(w.remove_note(nid)?, 0);
                    Ok(n)
                })
                .unwrap();
        }
        assert_eq!(removed as i64, card_count);

        let col = Collection::open(&out).unwrap();
        // Note and its cards are gone.
        assert_eq!(
            col.db
                .query_row("SELECT count(*) FROM notes WHERE id=?1", [nid], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
        assert_eq!(
            col.db
                .query_row("SELECT count(*) FROM cards WHERE nid=?1", [nid], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
        // One note grave (type 1) plus one card grave (type 0) per card, all
        // stamped with the pre-batch USN.
        let note_graves: i64 = col
            .db
            .query_row(
                "SELECT count(*) FROM graves WHERE oid=?1 AND type=1 AND usn=?2",
                params![nid, usn_before],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(note_graves, 1);
        let card_graves: i64 = col
            .db
            .query_row(
                "SELECT count(*) FROM graves WHERE type=0 AND usn=?1",
                [usn_before],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(card_graves, card_count);
        // Server-mode USN: one bump for the whole batch.
        assert_eq!(col.usn().unwrap(), usn_before + 1);
        // Left at `out` for the Check Database gate.
    }
}

