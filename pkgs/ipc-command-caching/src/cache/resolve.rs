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
    snapshot.iter().all(|(k, v)| client.get(k) == Some(v))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::schema::StaleConfig;

    fn make_cmd_config() -> CommandConfig {
        CommandConfig {
            run: "echo test".into(),
            shell: None,
            env: vec![],
            exec_in_cwd: false,
            interval: None,
            max_age: None,
            timeout: None,
            stale: None,
            check: None,
            check_interval: None,
            watch: vec![],
            idle_timeout: None,
        }
    }

    fn make_defaults() -> DefaultsSection {
        DefaultsSection::default()
    }

    #[test]
    fn empty_returns_empty_status_and_triggers_exec() {
        let entry = CacheEntry::new();
        let (status, _, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_EMPTY);
        assert!(should_exec);
    }

    #[test]
    fn cached_with_matching_env_returns_cached() {
        let mut entry = CacheEntry::new();
        entry.start();
        let mut env = HashMap::new();
        env.insert("CWD".into(), "/home".into());
        entry.complete("value".into(), env.clone());

        let (status, value, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &env);
        assert_eq!(status, STATUS_CACHED);
        assert_eq!(value, "value");
        assert!(!should_exec);
    }

    #[test]
    fn cached_with_mismatched_env_returns_stale_and_triggers() {
        let mut entry = CacheEntry::new();
        entry.start();
        let mut env1 = HashMap::new();
        env1.insert("CWD".into(), "/home".into());
        entry.complete("value".into(), env1);

        let mut env2 = HashMap::new();
        env2.insert("CWD".into(), "/other".into());

        let (status, _, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &env2);
        assert_eq!(status, STATUS_STALE);
        assert!(should_exec);
    }

    #[test]
    fn running_with_previous_value_returns_stale() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("old".into(), HashMap::new());
        entry.start(); // Cached → Running (previous_value = "old")

        let (status, value, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_STALE);
        assert_eq!(value, "old");
        assert!(!should_exec);
    }

    #[test]
    fn running_without_previous_value_returns_empty() {
        let mut entry = CacheEntry::new();
        entry.start(); // Empty → Running (no previous_value)

        let (status, _, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_EMPTY);
        assert!(!should_exec);
    }

    #[test]
    fn expired_triggers_exec() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("val".into(), HashMap::new());
        entry.check_expiry(std::time::Duration::ZERO);

        let (status, _, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_EXPIRED);
        assert!(should_exec);
    }

    #[test]
    fn errored_with_last_good_returns_stale() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("good".into(), HashMap::new());
        entry.start();
        entry.fail("oops".into());

        let (status, value, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_STALE);
        assert_eq!(value, "good");
        assert!(should_exec);
    }

    #[test]
    fn errored_without_last_good_returns_error() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.fail("oops".into());

        let (status, _, should_exec) = resolve(&entry, &make_cmd_config(), &make_defaults(), &HashMap::new());
        assert_eq!(status, STATUS_ERROR);
        assert!(should_exec);
    }

    #[test]
    fn custom_stale_config_used() {
        let mut cmd = make_cmd_config();
        cmd.stale = Some(StaleConfig {
            on_empty: "loading...".into(),
            on_context_mismatch: "switching...".into(),
            on_expired: "refreshing...".into(),
            on_error: "broken".into(),
        });

        let entry = CacheEntry::new();
        let (_, value, _) = resolve(&entry, &cmd, &make_defaults(), &HashMap::new());
        assert_eq!(value, "loading...");
    }

    #[test]
    fn env_matches_empty_snapshot_always_matches() {
        let snapshot = HashMap::new();
        let mut client = HashMap::new();
        client.insert("FOO".into(), "bar".into());
        assert!(env_matches(&snapshot, &client));
    }

    #[test]
    fn env_matches_subset_check() {
        let mut snapshot = HashMap::new();
        snapshot.insert("A".into(), "1".into());

        let mut client = HashMap::new();
        client.insert("A".into(), "1".into());
        client.insert("B".into(), "2".into());
        assert!(env_matches(&snapshot, &client));
    }

    #[test]
    fn env_matches_missing_key_fails() {
        let mut snapshot = HashMap::new();
        snapshot.insert("A".into(), "1".into());
        let client = HashMap::new();
        assert!(!env_matches(&snapshot, &client));
    }

    #[test]
    fn env_matches_different_value_fails() {
        let mut snapshot = HashMap::new();
        snapshot.insert("A".into(), "1".into());
        let mut client = HashMap::new();
        client.insert("A".into(), "2".into());
        assert!(!env_matches(&snapshot, &client));
    }
}
