use std::collections::HashMap;

use super::entry::CacheEntry;
use crate::config::schema::{CommandConfig, DefaultsSection};

/// Status byte values sent in the wire protocol response.
pub const STATUS_CACHED: u8 = 0x01;
pub const STATUS_STALE: u8 = 0x02;
pub const STATUS_EXPIRED: u8 = 0x03;
pub const STATUS_EMPTY: u8 = 0x04;
pub const STATUS_ERROR: u8 = 0x05;

/// Resolve a response from the current cache state.
///
/// Returns `(status_byte, display_value, should_trigger_execution)`.
pub fn resolve(
    entry: &CacheEntry,
    cmd_config: &CommandConfig,
    defaults: &DefaultsSection,
    client_env: &HashMap<String, String>,
) -> (u8, String, bool) {
    let stale = cmd_config.effective_stale(defaults);

    match entry {
        CacheEntry::Empty(_) => (STATUS_EMPTY, stale.on_empty.clone(), true),

        CacheEntry::Running(r) => match &r.previous_value {
            Some(v) => (STATUS_STALE, v.clone(), false),
            None => (STATUS_EMPTY, stale.on_empty.clone(), false),
        },

        CacheEntry::Cached(c) => {
            if env_matches(&c.env_snapshot, client_env) {
                (STATUS_CACHED, c.value.clone(), false)
            } else {
                // Context mismatch — return stale indicator and trigger re-execution
                (STATUS_STALE, stale.on_context_mismatch.clone(), true)
            }
        }

        CacheEntry::Expired(_) => (STATUS_EXPIRED, stale.on_expired.clone(), true),

        CacheEntry::Errored(e) => match &e.last_good_value {
            Some(v) => (STATUS_STALE, v.clone(), true),
            None => (STATUS_ERROR, stale.on_error.clone(), true),
        },
    }
}

/// Check if all env vars in the snapshot match the client's current values.
fn env_matches(snapshot: &HashMap<String, String>, client: &HashMap<String, String>) -> bool {
    snapshot.iter().all(|(k, v)| client.get(k).map_or(false, |cv| cv == v))
}
