use clap::{Arg, ArgAction, Command, crate_version};
use fuser::{
    FileAttr, FileType, Filesystem, MountOption, ReplyAttr, ReplyData, ReplyDirectory, ReplyEntry,
    Request,
};
use libc::ENOENT;
use std::ffi::OsStr;
use std::time::{Duration, UNIX_EPOCH};
use sqlx::{SqlitePool, Row};
use fuse_taskchampion::{Note, Blob, Branch};

const TTL: Duration = Duration::from_secs(1);
const ROOT_INO: u64 = 1;

struct TriliumFS {
    pool: SqlitePool,
    runtime: tokio::runtime::Runtime,
}

impl TriliumFS {
    fn new(pool: SqlitePool, runtime: tokio::runtime::Runtime) -> Self {
        Self { pool, runtime }
    }

    /// Convert noteId to inode number (simple hash for now)
    fn note_id_to_ino(note_id: &str) -> u64 {
        if note_id == "root" {
            return ROOT_INO;
        }
        // Simple hash - could be improved
        let mut hash: u64 = 0;
        for byte in note_id.bytes() {
            hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
        }
        // Ensure it's not 0 or 1 (reserved)
        if hash <= 1 {
            hash + 2
        } else {
            hash
        }
    }

    /// Check if a note has children
    fn has_children(&self, note_id: &str) -> bool {
        self.runtime.block_on(async {
            let result = sqlx::query(
                "SELECT COUNT(*) as count FROM branches WHERE parentNoteId = ? AND isDeleted = 0"
            )
            .bind(note_id)
            .fetch_one(&self.pool)
            .await;

            if let Ok(row) = result {
                let count: i64 = row.get("count");
                count > 0
            } else {
                false
            }
        })
    }

    /// Get note by ID
    fn get_note(&self, note_id: &str) -> Option<Note> {
        self.runtime.block_on(async {
            sqlx::query_as::<_, Note>(
                "SELECT * FROM notes WHERE noteId = ? AND isDeleted = 0"
            )
            .bind(note_id)
            .fetch_optional(&self.pool)
            .await
            .ok()
            .flatten()
        })
    }

    /// Get root directory attributes
    fn get_root_attr() -> FileAttr {
        FileAttr {
            ino: ROOT_INO,
            size: 0,
            blocks: 0,
            atime: UNIX_EPOCH,
            mtime: UNIX_EPOCH,
            ctime: UNIX_EPOCH,
            crtime: UNIX_EPOCH,
            kind: FileType::Directory,
            perm: 0o755,
            nlink: 2,
            uid: 501,
            gid: 20,
            rdev: 0,
            flags: 0,
            blksize: 512,
        }
    }
}

impl Filesystem for TriliumFS {
    fn lookup(&mut self, _req: &Request, parent: u64, name: &OsStr, reply: ReplyEntry) {
        let name_str = match name.to_str() {
            Some(s) => s,
            None => {
                eprintln!("lookup: name is not valid UTF-8");
                reply.error(ENOENT);
                return;
            }
        };

        eprintln!("lookup: parent={}, name={}", parent, name_str);

        // Determine parent note ID
        let parent_note_id = if parent == ROOT_INO {
            "root".to_string()
        } else {
            // Find note ID from inode
            let found = self.runtime.block_on(async {
                let notes = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE isDeleted = 0 LIMIT 1000"
                )
                .fetch_all(&self.pool)
                .await
                .ok()?;

                for note in notes {
                    if Self::note_id_to_ino(&note.note_id) == parent {
                        return Some(note.note_id);
                    }
                }
                None
            });

            match found {
                Some(id) => id,
                None => {
                    reply.error(ENOENT);
                    return;
                }
            }
        };

        // Check if this is a hidden content file lookup (e.g., ".NoteName.md")
        if name_str.starts_with('.') && parent != ROOT_INO {
            // This should be the content file for the parent directory
            let pool = &self.pool;
            let result = self.runtime.block_on(async {
                let parent_note = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE noteId = ? AND isDeleted = 0"
                )
                .bind(&parent_note_id)
                .fetch_one(pool)
                .await
                .ok()?;

                let expected_name = format!(".{}", parent_note.filename());
                if name_str != expected_name {
                    return None;
                }

                // Get blob size
                let size = if let Some(ref blob_id) = parent_note.blob_id {
                    let blob = sqlx::query_as::<_, Blob>(
                        "SELECT * FROM blobs WHERE blobId = ?"
                    )
                    .bind(blob_id)
                    .fetch_one(pool)
                    .await
                    .ok()?;
                    blob.content.as_ref().map(|c| c.len() as u64).unwrap_or(0)
                } else {
                    0
                };

                Some(parent_note.to_file_attr(parent, size))
            });

            if let Some(attr) = result {
                reply.entry(&TTL, &attr, 0);
                return;
            }
        }

        // Query for child notes
        eprintln!("  querying for branches with parentNoteId='{}'", parent_note_id);
        let pool = &self.pool;
        let result = self.runtime.block_on(async {
            let branches = sqlx::query_as::<_, Branch>(
                "SELECT * FROM branches WHERE parentNoteId = ? AND isDeleted = 0"
            )
            .bind(&parent_note_id)
            .fetch_all(pool)
            .await?;

            eprintln!("  found {} branches under parent", branches.len());

            // Find matching note
            for branch in branches {
                let note = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE noteId = ? AND isDeleted = 0"
                )
                .bind(&branch.note_id)
                .fetch_one(pool)
                .await?;

                // Check if note has children (inline to avoid nested block_on)
                let child_count: i64 = sqlx::query(
                    "SELECT COUNT(*) as count FROM branches WHERE parentNoteId = ? AND isDeleted = 0"
                )
                .bind(&note.note_id)
                .fetch_one(pool)
                .await?
                .get("count");

                let has_children = child_count > 0;

                // Check if name matches
                let matches = if has_children {
                    // Directory: match by title
                    eprintln!("  checking dir: '{}' == '{}' ? {}", note.title, name_str, note.title == name_str);
                    note.title == name_str
                } else {
                    // File: match by filename
                    eprintln!("  checking file: '{}' == '{}' ? {}", note.filename(), name_str, note.filename() == name_str);
                    note.filename() == name_str
                };

                if matches {
                    let ino = Self::note_id_to_ino(&note.note_id);

                    if has_children {
                        // Return directory attributes
                        let attr = FileAttr {
                            ino,
                            size: 0,
                            blocks: 0,
                            atime: UNIX_EPOCH,
                            mtime: UNIX_EPOCH,
                            ctime: UNIX_EPOCH,
                            crtime: UNIX_EPOCH,
                            kind: FileType::Directory,
                            perm: 0o755,
                            nlink: 2,
                            uid: 501,
                            gid: 20,
                            rdev: 0,
                            flags: 0,
                            blksize: 512,
                        };
                        return Ok::<_, sqlx::Error>(attr);
                    } else {
                        // Return file attributes
                        let size = if let Some(ref blob_id) = note.blob_id {
                            let blob = sqlx::query_as::<_, Blob>(
                                "SELECT * FROM blobs WHERE blobId = ?"
                            )
                            .bind(blob_id)
                            .fetch_one(pool)
                            .await?;
                            blob.content.as_ref().map(|c| c.len() as u64).unwrap_or(0)
                        } else {
                            0
                        };

                        let attr = note.to_file_attr(ino, size);
                        return Ok::<_, sqlx::Error>(attr);
                    }
                }
            }
            Err(sqlx::Error::RowNotFound)
        });

        match result {
            Ok(attr) => {
                eprintln!("lookup: found! returning attr: kind={:?}, perm={:#o}", attr.kind, attr.perm);
                reply.entry(&TTL, &attr, 0)
            },
            Err(e) => {
                eprintln!("lookup: NOT FOUND for parent={}, name={}: {:?}", parent, name_str, e);
                reply.error(ENOENT)
            },
        }
    }

    fn getattr(&mut self, _req: &Request, ino: u64, _fh: Option<u64>, reply: ReplyAttr) {
        if ino == ROOT_INO {
            reply.attr(&TTL, &Self::get_root_attr());
            return;
        }

        // Query database for note by searching all notes and matching ino
        let pool = &self.pool;
        let result = self.runtime.block_on(async {
            let notes = sqlx::query_as::<_, Note>(
                "SELECT * FROM notes WHERE isDeleted = 0 LIMIT 1000"
            )
            .fetch_all(pool)
            .await?;

            for note in notes {
                if Self::note_id_to_ino(&note.note_id) == ino {
                    // Check if note has children (inline to avoid nested block_on)
                    let child_count: i64 = sqlx::query(
                        "SELECT COUNT(*) as count FROM branches WHERE parentNoteId = ? AND isDeleted = 0"
                    )
                    .bind(&note.note_id)
                    .fetch_one(pool)
                    .await?
                    .get("count");

                    let has_children = child_count > 0;

                    eprintln!("getattr: ino={}, note={}, has_children={}", ino, note.title, has_children);

                    if has_children {
                        // Return directory attributes
                        let attr = FileAttr {
                            ino,
                            size: 0,
                            blocks: 0,
                            atime: UNIX_EPOCH,
                            mtime: UNIX_EPOCH,
                            ctime: UNIX_EPOCH,
                            crtime: UNIX_EPOCH,
                            kind: FileType::Directory,
                            perm: 0o755,
                            nlink: 2,
                            uid: 1000,
                            gid: 100,
                            rdev: 0,
                            flags: 0,
                            blksize: 512,
                        };
                        eprintln!("  returning dir attr with perm={:#o}", attr.perm);
                        return Ok::<_, sqlx::Error>(attr);
                    } else {
                        // Return file attributes
                        let size = if let Some(ref blob_id) = note.blob_id {
                            let blob = sqlx::query_as::<_, Blob>(
                                "SELECT * FROM blobs WHERE blobId = ?"
                            )
                            .bind(blob_id)
                            .fetch_one(pool)
                            .await?;
                            blob.content.as_ref().map(|c| c.len() as u64).unwrap_or(0)
                        } else {
                            0
                        };

                        let attr = note.to_file_attr(ino, size);
                        return Ok::<_, sqlx::Error>(attr);
                    }
                }
            }
            Err(sqlx::Error::RowNotFound)
        });

        match result {
            Ok(attr) => {
                eprintln!("getattr: replying with attr: kind={:?}, perm={:#o}", attr.kind, attr.perm);
                reply.attr(&TTL, &attr)
            },
            Err(e) => {
                eprintln!("getattr: error for ino={}: {:?}", ino, e);
                reply.error(ENOENT)
            },
        }
    }

    fn read(
        &mut self,
        _req: &Request,
        ino: u64,
        _fh: u64,
        offset: i64,
        _size: u32,
        _flags: i32,
        _lock: Option<u64>,
        reply: ReplyData,
    ) {
        // Find note by inode and return content
        let pool = &self.pool;
        let result = self.runtime.block_on(async {
            let notes = sqlx::query_as::<_, Note>(
                "SELECT * FROM notes WHERE isDeleted = 0 LIMIT 1000"
            )
            .fetch_all(pool)
            .await?;

            for note in notes {
                if Self::note_id_to_ino(&note.note_id) == ino {
                    // Get blob content
                    if let Some(ref blob_id) = note.blob_id {
                        let blob = sqlx::query_as::<_, Blob>(
                            "SELECT * FROM blobs WHERE blobId = ?"
                        )
                        .bind(blob_id)
                        .fetch_one(pool)
                        .await?;

                        if let Some(content) = blob.content {
                            return Ok::<_, sqlx::Error>(content);
                        }
                    }
                    // Empty content
                    return Ok(Vec::new());
                }
            }
            Err(sqlx::Error::RowNotFound)
        });

        match result {
            Ok(content) => {
                let offset = offset as usize;
                if offset < content.len() {
                    reply.data(&content[offset..]);
                } else {
                    reply.data(&[]);
                }
            }
            Err(_) => reply.error(ENOENT),
        }
    }

    fn readdir(
        &mut self,
        _req: &Request,
        ino: u64,
        _fh: u64,
        offset: i64,
        mut reply: ReplyDirectory,
    ) {
        // Determine parent note ID
        let parent_note_id = if ino == ROOT_INO {
            "root".to_string()
        } else {
            // Find note ID from inode (inefficient but works for now)
            let found = self.runtime.block_on(async {
                let notes = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE isDeleted = 0 LIMIT 1000"
                )
                .fetch_all(&self.pool)
                .await
                .ok()?;

                for note in notes {
                    if Self::note_id_to_ino(&note.note_id) == ino {
                        return Some(note.note_id);
                    }
                }
                None
            });

            match found {
                Some(id) => id,
                None => {
                    reply.error(ENOENT);
                    return;
                }
            }
        };

        // Query database for child notes - do everything in one async block
        let pool = &self.pool;
        let entries_result = self.runtime.block_on(async {
            let mut entries = vec![
                (ino, FileType::Directory, ".".to_string()),
                (ino, FileType::Directory, "..".to_string()),
            ];

            // If not root, add the hidden content file for this directory
            if ino != ROOT_INO {
                if let Ok(note) = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE noteId = ? AND isDeleted = 0"
                )
                .bind(&parent_note_id)
                .fetch_one(pool)
                .await {
                    let content_filename = format!(".{}", note.filename());
                    entries.push((ino, FileType::RegularFile, content_filename));
                }
            }

            // Get child branches
            let branches = sqlx::query_as::<_, Branch>(
                "SELECT * FROM branches WHERE parentNoteId = ? AND isDeleted = 0 ORDER BY notePosition"
            )
            .bind(&parent_note_id)
            .fetch_all(pool)
            .await?;

            // Fetch note details for each branch
            for branch in branches {
                if let Ok(note) = sqlx::query_as::<_, Note>(
                    "SELECT * FROM notes WHERE noteId = ? AND isDeleted = 0"
                )
                .bind(&branch.note_id)
                .fetch_one(pool)
                .await {
                    let child_ino = Self::note_id_to_ino(&note.note_id);

                    // Check if has children
                    let child_count: i64 = sqlx::query(
                        "SELECT COUNT(*) as count FROM branches WHERE parentNoteId = ? AND isDeleted = 0"
                    )
                    .bind(&note.note_id)
                    .fetch_one(pool)
                    .await?
                    .get("count");

                    let has_children = child_count > 0;

                    if has_children {
                        // Show as directory
                        entries.push((child_ino, FileType::Directory, note.title.clone()));
                    } else {
                        // Show as file
                        let filename = note.filename();
                        entries.push((child_ino, FileType::RegularFile, filename));
                    }
                }
            }

            Ok::<_, sqlx::Error>(entries)
        });

        let entries = match entries_result {
            Ok(e) => e,
            Err(_) => {
                reply.error(ENOENT);
                return;
            }
        };

        for (i, entry) in entries.into_iter().enumerate().skip(offset as usize) {
            if reply.add(entry.0, (i + 1) as i64, entry.1, &entry.2) {
                break;
            }
        }
        reply.ok();
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let matches = Command::new("trilium-fuse")
        .version(crate_version!())
        .author("Trilium FUSE Filesystem")
        .arg(
            Arg::new("MOUNT_POINT")
                .required(true)
                .index(1)
                .help("Act as a client, and mount FUSE at given path"),
        )
        .arg(
            Arg::new("database")
                .long("database")
                .short('d')
                .value_name("PATH")
                .help("Path to Trilium SQLite database (defaults to DATABASE_URL env)"),
        )
        .arg(
            Arg::new("auto_unmount")
                .long("auto_unmount")
                .action(ArgAction::SetTrue)
                .help("Automatically unmount on process exit"),
        )
        .arg(
            Arg::new("allow-root")
                .long("allow-root")
                .action(ArgAction::SetTrue)
                .help("Allow root user to access filesystem"),
        )
        .get_matches();

    env_logger::init();

    // Get database URL
    let db_url = if let Some(path) = matches.get_one::<String>("database") {
        format!("sqlite://{}", path)
    } else {
        std::env::var("DATABASE_URL")
            .unwrap_or_else(|_| "sqlite://.fuse-fs.db".to_string())
    };

    println!("Connecting to database: {}", db_url);

    // Create runtime for async operations
    let runtime = tokio::runtime::Runtime::new()?;

    // Create database pool and run migrations
    let pool = runtime.block_on(async {
        let pool = SqlitePool::connect(&db_url).await?;
        sqlx::migrate!("./migrations").run(&pool).await?;
        Ok::<_, Box<dyn std::error::Error>>(pool)
    })?;

    println!("Database initialized successfully");

    let mountpoint = matches.get_one::<String>("MOUNT_POINT").unwrap();
    let mut options = vec![MountOption::RO, MountOption::FSName("trilium".to_string())];
    if matches.get_flag("auto_unmount") {
        options.push(MountOption::AutoUnmount);
    }
    if matches.get_flag("allow-root") {
        options.push(MountOption::AllowRoot);
    }

    let fs = TriliumFS::new(pool, runtime);

    println!("Mounting at: {}", mountpoint);
    fuser::mount2(fs, mountpoint, &options)?;

    Ok(())
}
