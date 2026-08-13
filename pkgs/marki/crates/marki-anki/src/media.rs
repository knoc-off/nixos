//! Server-side media database (schema v4).
//!
//! This is a *separate* SQLite file from the collection -- in the sync-server
//! layout it lives beside `collection.anki2` as `media.db`, with the actual
//! files under `media/`. Its schema is **not** the desktop client's
//! `collection.media.db2`; only the server schema applies here
//! (`rslib/src/sync/media/database/server/`).
//!
//! Two things make this database subtle, and both are reproduced from rslib
//! rather than guessed:
//!
//! 1. **Media has its own USN counter.** Unlike the collection (one server-USN
//!    bump per sync batch), every media entry mutation advances `meta.last_usn`
//!    by one and stamps that value on the row. The counter lives in `meta`, not
//!    in the collection's `col.usn`.
//! 2. **Deletions are tombstones, not row removals.** Removing a file sets its
//!    `size` to 0 (keeping the `csum`) and advances its usn, so peers learn the
//!    file is gone. The `meta` aggregates (`total_bytes`,
//!    `total_nonempty_files`) must stay consistent with the surviving rows.

use anyhow::{Context, Result, bail};
use rusqlite::{Connection, OptionalExtension, params};
use sha1::{Digest, Sha1};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// The only media schema version we operate on. anki-sync-server creates the
/// database at this version; we refuse anything else rather than migrate.
pub const MEDIA_VER: u32 = 4;

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// An open server media database, guarded to v4.
pub struct MediaDatabase {
    db: Connection,
}

/// The `meta` row: aggregates that must always agree with the `media` rows.
/// Mirror of rslib's `StoreMetadata`.
struct Meta {
    last_usn: i64,
    total_bytes: i64,
    total_nonempty_files: i64,
}

impl Meta {
    /// Advance and return the media usn (`StoreMetadata::next_usn`).
    fn next_usn(&mut self) -> i64 {
        self.last_usn += 1;
        self.last_usn
    }
}

/// An existing `media` row, enough to account for a replace/remove.
struct Entry {
    csum: Vec<u8>,
    size: i64,
}

impl MediaDatabase {
    /// Open an existing media database or create a fresh one at `path`. A fresh
    /// file is built by running rslib's own `schema_v3` then `schema_v4`
    /// migrations verbatim, so the result is byte-compatible with what
    /// anki-sync-server would create itself. An existing file must already be
    /// at v4.
    pub fn open_or_create(path: &Path) -> Result<Self> {
        let db = Connection::open(path)
            .with_context(|| format!("open media db {}", path.display()))?;
        // Match rslib's `open_or_create_db` pragmas.
        db.pragma_update(None, "locking_mode", "exclusive")
            .context("set media locking_mode")?;
        db.pragma_update(None, "journal_mode", "wal")
            .context("set media journal_mode")?;

        let ver: u32 = db
            .query_row("SELECT user_version FROM pragma_user_version", [], |r| r.get(0))
            .context("read media user_version")?;
        if ver == 0 {
            // Brand-new file: run the exact rslib migration chain.
            db.execute_batch(include_str!("../media/schema_v3.sql"))
                .context("apply media schema_v3")?;
            db.execute_batch(include_str!("../media/schema_v4.sql"))
                .context("apply media schema_v4")?;
        } else if ver != MEDIA_VER {
            bail!("unsupported media db version {ver}; expected {MEDIA_VER}");
        }
        Ok(Self { db })
    }

    fn read_meta(&self) -> Result<Meta> {
        self.db
            .query_row(
                "SELECT last_usn, total_bytes, total_nonempty_files FROM meta",
                [],
                |r| {
                    Ok(Meta {
                        last_usn: r.get(0)?,
                        total_bytes: r.get(1)?,
                        total_nonempty_files: r.get(2)?,
                    })
                },
            )
            .context("read media meta")
    }

    /// Current media usn (`meta.last_usn`).
    pub fn last_usn(&self) -> Result<i64> {
        Ok(self.read_meta()?.last_usn)
    }

    /// Number of files that still exist (`size > 0`).
    pub fn nonempty_file_count(&self) -> Result<i64> {
        Ok(self.read_meta()?.total_nonempty_files)
    }

    /// Total bytes across surviving files.
    pub fn total_bytes(&self) -> Result<i64> {
        Ok(self.read_meta()?.total_bytes)
    }

    /// Run a batch of media mutations inside a single `BEGIN EXCLUSIVE`
    /// transaction, flushing the updated `meta` aggregates on success. Mirrors
    /// rslib's `with_transaction`: the in-memory `Meta` is loaded once, mutated
    /// by each op, and written back before commit. On any error the
    /// transaction rolls back and the file is untouched.
    pub fn transact<T>(&mut self, f: impl FnOnce(&mut MediaWriter) -> Result<T>) -> Result<T> {
        let tx = self
            .db
            .transaction_with_behavior(rusqlite::TransactionBehavior::Exclusive)
            .context("begin exclusive media transaction")?;

        let mut meta = tx
            .query_row(
                "SELECT last_usn, total_bytes, total_nonempty_files FROM meta",
                [],
                |r| {
                    Ok(Meta {
                        last_usn: r.get(0)?,
                        total_bytes: r.get(1)?,
                        total_nonempty_files: r.get(2)?,
                    })
                },
            )
            .context("read media meta")?;

        let out = {
            let mut w = MediaWriter { tx: &tx, meta: &mut meta };
            f(&mut w)?
        };

        tx.execute(
            "UPDATE meta SET last_usn = ?1, total_bytes = ?2, total_nonempty_files = ?3",
            params![meta.last_usn, meta.total_bytes, meta.total_nonempty_files],
        )
        .context("flush media meta")?;
        tx.commit().context("commit media transaction")?;
        Ok(out)
    }
}

/// Mutation handle scoped to one media [`transact`](MediaDatabase::transact)
/// batch. Holds the running `meta` so aggregates and per-entry usns stay
/// consistent across the batch.
pub struct MediaWriter<'a> {
    tx: &'a rusqlite::Transaction<'a>,
    meta: &'a mut Meta,
}

impl MediaWriter<'_> {
    fn get_entry(&self, fname: &str) -> Result<Option<Entry>> {
        Ok(self
            .tx
            .query_row(
                "SELECT csum, size FROM media WHERE fname = ?1",
                [fname],
                |r| Ok(Entry { csum: r.get(0)?, size: r.get(1)? }),
            )
            .optional()?)
    }

    /// `INSERT OR REPLACE` a media row (rslib `set_entry.sql`).
    fn set_entry(&self, fname: &str, csum: &[u8], size: i64, usn: i64, mtime: i64) -> Result<()> {
        self.tx
            .execute(
                "INSERT OR REPLACE INTO media (fname, csum, size, usn, mtime) \
                 VALUES (?1, ?2, ?3, ?4, ?5)",
                params![fname, csum, size, usn, mtime],
            )
            .with_context(|| format!("set media entry {fname:?}"))?;
        Ok(())
    }

    /// Add or update a media file from its raw bytes. The `csum` is the SHA-1
    /// of the contents and `size` the byte length, exactly as rslib records
    /// them. If the file already exists with the same checksum and size this is
    /// a no-op (so re-running marki does not churn usns); otherwise the entry
    /// is (re)written and the media usn advances by one. Empty input is treated
    /// as a deletion, since a zero `size` is Anki's tombstone marker.
    pub fn upsert_file(&mut self, fname: &str, data: &[u8]) -> Result<()> {
        if data.is_empty() {
            return self.remove_file(fname);
        }
        let csum = Sha1::digest(data).to_vec();
        let size = data.len() as i64;

        match self.get_entry(fname)? {
            Some(e) if e.size > 0 => {
                // Unchanged: leave the row (and usn) alone.
                if e.size == size && e.csum == csum {
                    return Ok(());
                }
                // replace_entry: adjust total_bytes by the size delta.
                self.meta.total_bytes = self.meta.total_bytes - e.size + size;
            }
            _ => {
                // add_entry (no row, or resurrecting a tombstone): a new
                // nonempty file appears.
                self.meta.total_bytes += size;
                self.meta.total_nonempty_files += 1;
            }
        }
        let usn = self.meta.next_usn();
        self.set_entry(fname, &csum, size, usn, now_secs())
    }

    /// Tombstone a media file: keep its `csum`, set `size` to 0, and advance
    /// the media usn so peers learn it was deleted (rslib `remove_entry`).
    /// No-op if the file is absent or already a tombstone.
    pub fn remove_file(&mut self, fname: &str) -> Result<()> {
        let Some(e) = self.get_entry(fname)? else {
            return Ok(());
        };
        if e.size == 0 {
            return Ok(());
        }
        self.meta.total_bytes -= e.size;
        self.meta.total_nonempty_files -= 1;
        let usn = self.meta.next_usn();
        // csum is retained on deletion (schema_v4: "csum is no longer nulled").
        self.set_entry(fname, &e.csum, 0, usn, now_secs())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Recompute the `meta` aggregates straight from the `media` rows and
    /// require the stored aggregates match. This is exactly the invariant
    /// rslib's schema_v4 migration establishes, so holding it means the file is
    /// internally consistent the way anki-sync-server expects.
    fn assert_meta_consistent(db: &MediaDatabase) {
        let (max_usn, sum_bytes, nonempty): (i64, i64, i64) = db
            .db
            .query_row(
                "SELECT coalesce(max(usn), 0), coalesce(sum(size), 0), \
                 coalesce(sum(size > 0), 0) FROM media",
                [],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .unwrap();
        let m = db.read_meta().unwrap();
        assert_eq!(m.last_usn, max_usn, "last_usn tracks max row usn");
        assert_eq!(m.total_bytes, sum_bytes, "total_bytes tracks sum(size)");
        assert_eq!(
            m.total_nonempty_files, nonempty,
            "total_nonempty_files tracks count(size>0)"
        );
    }

    #[test]
    fn fresh_db_has_v4_schema_and_zeroed_meta() {
        let dir = tempdir();
        let path = dir.join("media.db");
        let db = MediaDatabase::open_or_create(&path).unwrap();

        let ver: u32 = db
            .db
            .query_row("SELECT user_version FROM pragma_user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(ver, MEDIA_VER);

        // v4 shape: media(fname,csum,size,usn,mtime) + meta with three columns.
        let media_cols: Vec<String> = column_names(&db, "media");
        assert_eq!(media_cols, ["fname", "csum", "size", "usn", "mtime"]);
        let meta_cols: Vec<String> = column_names(&db, "meta");
        assert_eq!(meta_cols, ["last_usn", "total_bytes", "total_nonempty_files"]);

        assert_eq!(db.last_usn().unwrap(), 0);
        assert_eq!(db.total_bytes().unwrap(), 0);
        assert_eq!(db.nonempty_file_count().unwrap(), 0);
        assert_meta_consistent(&db);
    }

    #[test]
    fn add_replace_remove_keeps_meta_consistent() {
        let dir = tempdir();
        let path = dir.join("media.db");
        let mut db = MediaDatabase::open_or_create(&path).unwrap();

        db.transact(|w| {
            w.upsert_file("a.png", b"hello")?; // usn 1
            w.upsert_file("b.jpg", b"world!!")?; // usn 2
            Ok(())
        })
        .unwrap();
        assert_eq!(db.last_usn().unwrap(), 2);
        assert_eq!(db.nonempty_file_count().unwrap(), 2);
        assert_eq!(db.total_bytes().unwrap(), 5 + 7);
        assert_meta_consistent(&db);

        // Re-adding identical content is a no-op: no usn churn.
        db.transact(|w| w.upsert_file("a.png", b"hello")).unwrap();
        assert_eq!(db.last_usn().unwrap(), 2, "identical upsert must not bump usn");

        // Replacing content adjusts total_bytes and bumps usn.
        db.transact(|w| w.upsert_file("a.png", b"hello world")).unwrap();
        assert_eq!(db.last_usn().unwrap(), 3);
        assert_eq!(db.total_bytes().unwrap(), 11 + 7);
        assert_meta_consistent(&db);

        // Removing tombstones the row (size 0, csum kept) and bumps usn.
        db.transact(|w| w.remove_file("b.jpg")).unwrap();
        assert_eq!(db.last_usn().unwrap(), 4);
        assert_eq!(db.nonempty_file_count().unwrap(), 1);
        assert_eq!(db.total_bytes().unwrap(), 11);
        assert_meta_consistent(&db);

        let (size, csum_len): (i64, i64) = db
            .db
            .query_row(
                "SELECT size, length(csum) FROM media WHERE fname='b.jpg'",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(size, 0, "deleted file is a tombstone, not a removed row");
        assert_eq!(csum_len, 20, "sha1 csum is retained on deletion");

        // Removing an already-deleted or absent file is a no-op.
        db.transact(|w| {
            w.remove_file("b.jpg")?;
            w.remove_file("nope.gif")?;
            Ok(())
        })
        .unwrap();
        assert_eq!(db.last_usn().unwrap(), 4, "no-op removes must not bump usn");
        assert_meta_consistent(&db);
    }

    #[test]
    fn existing_v4_db_reopens_and_wrong_version_is_rejected() {
        let dir = tempdir();
        let path = dir.join("media.db");
        MediaDatabase::open_or_create(&path).unwrap();
        // Reopening an existing v4 file succeeds without re-running migrations.
        MediaDatabase::open_or_create(&path).unwrap();

        // A file at an unsupported version is refused, not silently migrated.
        let bad = dir.join("bad.db");
        let conn = Connection::open(&bad).unwrap();
        conn.pragma_update(None, "user_version", 99).unwrap();
        drop(conn);
        assert!(MediaDatabase::open_or_create(&bad).is_err());
    }

    fn column_names(db: &MediaDatabase, table: &str) -> Vec<String> {
        let mut stmt = db
            .db
            .prepare(&format!("SELECT name FROM pragma_table_info('{table}')"))
            .unwrap();
        stmt.query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .map(|r| r.unwrap())
            .collect()
    }

    fn tempdir() -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let base = std::env::temp_dir();
        // Unique per call so parallel tests never share a media.db path.
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let d = base.join(format!("marki-media-test-{}-{n}-{nanos}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }
}
