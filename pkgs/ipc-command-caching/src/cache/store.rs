use std::collections::HashMap;

use tokio::time::Instant;

use super::entry::CacheEntry;

/// Tracks request activity for a cache key (hot/cold determination).
pub struct ActivityTracker {
    pub last_requested_at: Instant,
    pub request_count: u64,
}

impl ActivityTracker {
    pub fn new() -> Self {
        Self {
            last_requested_at: Instant::now(),
            request_count: 0,
        }
    }

    pub fn touch(&mut self) {
        self.last_requested_at = Instant::now();
        self.request_count += 1;
    }

    pub fn is_hot(&self, idle_timeout: std::time::Duration) -> bool {
        self.last_requested_at.elapsed() < idle_timeout
    }
}

/// Per-key entry combining cache state and activity tracking.
pub struct StoreEntry {
    pub cache: CacheEntry,
    pub activity: ActivityTracker,
    /// Last env vars received from a client request (carried forward for scheduler re-executions).
    pub last_env: HashMap<String, String>,
}

impl StoreEntry {
    pub fn new() -> Self {
        Self {
            cache: CacheEntry::new(),
            activity: ActivityTracker::new(),
            last_env: HashMap::new(),
        }
    }
}

/// The main cache store: maps resolved keys to their entries.
pub struct CacheStore {
    entries: HashMap<String, StoreEntry>,
}

impl CacheStore {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    /// Get or create an entry for a resolved key.
    pub fn get_or_create(&mut self, key: &str) -> &mut StoreEntry {
        self.entries
            .entry(key.to_string())
            .or_insert_with(StoreEntry::new)
    }

    pub fn get(&self, key: &str) -> Option<&StoreEntry> {
        self.entries.get(key)
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut StoreEntry> {
        self.entries.get_mut(key)
    }

    pub fn remove(&mut self, key: &str) -> Option<StoreEntry> {
        self.entries.remove(key)
    }

    /// Iterate all entries (for status dump).
    pub fn iter(&self) -> impl Iterator<Item = (&String, &StoreEntry)> {
        self.entries.iter()
    }

    /// Remove entries whose command names are no longer in the config.
    pub fn retain_commands(&mut self, valid_prefixes: &[String]) {
        self.entries.retain(|key, _| {
            valid_prefixes.iter().any(|prefix| key.contains(prefix))
        });
    }
}
