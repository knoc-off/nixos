use std::collections::HashMap;

use super::state::{Cached, Empty, Errored, Expired, Running};

/// Runtime wrapper enum over the typestate cache states.
/// Mediates transitions via match arms; the compiler enforces exhaustive handling.
#[derive(Debug)]
pub enum CacheEntry {
    Empty(Empty),
    Running(Running),
    Cached(Cached),
    Expired(Expired),
    Errored(Errored),
}

impl CacheEntry {
    pub fn new() -> Self {
        CacheEntry::Empty(Empty)
    }

    /// Attempt to start execution. Returns true if the transition happened.
    pub fn start(&mut self) -> bool {
        let prev = std::mem::replace(self, CacheEntry::Empty(Empty));
        match prev {
            CacheEntry::Empty(s) => {
                *self = CacheEntry::Running(s.start());
                true
            }
            CacheEntry::Cached(s) => {
                *self = CacheEntry::Running(s.refresh());
                true
            }
            CacheEntry::Expired(s) => {
                *self = CacheEntry::Running(s.retry());
                true
            }
            CacheEntry::Errored(s) => {
                *self = CacheEntry::Running(s.retry());
                true
            }
            CacheEntry::Running(_) => {
                // Already running — put it back
                *self = prev;
                false
            }
        }
    }

    /// Record a successful command completion.
    pub fn complete(&mut self, value: String, env: HashMap<String, String>) {
        let prev = std::mem::replace(self, CacheEntry::Empty(Empty));
        match prev {
            CacheEntry::Running(s) => {
                *self = CacheEntry::Cached(s.complete(value, env));
            }
            other => {
                // Shouldn't happen — restore and log
                *self = other;
                tracing::warn!("complete() called on non-Running entry");
            }
        }
    }

    /// Record a command failure.
    pub fn fail(&mut self, error: String) {
        let prev = std::mem::replace(self, CacheEntry::Empty(Empty));
        match prev {
            CacheEntry::Running(s) => {
                *self = CacheEntry::Errored(s.fail(error));
            }
            other => {
                *self = other;
                tracing::warn!("fail() called on non-Running entry");
            }
        }
    }

    /// Check if max_age is exceeded and transition Cached → Expired.
    pub fn check_expiry(&mut self, max_age: std::time::Duration) {
        let should_expire = matches!(self, CacheEntry::Cached(c) if c.computed_at.elapsed() > max_age);
        if should_expire {
            let prev = std::mem::replace(self, CacheEntry::Empty(Empty));
            if let CacheEntry::Cached(s) = prev {
                *self = CacheEntry::Expired(s.expire());
            }
        }
    }

    pub fn is_running(&self) -> bool {
        matches!(self, CacheEntry::Running(_))
    }

    pub fn state_name(&self) -> &'static str {
        match self {
            CacheEntry::Empty(_) => "Empty",
            CacheEntry::Running(_) => "Running",
            CacheEntry::Cached(_) => "Cached",
            CacheEntry::Expired(_) => "Expired",
            CacheEntry::Errored(_) => "Errored",
        }
    }
}

impl Default for CacheEntry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn new_is_empty() {
        let entry = CacheEntry::new();
        assert_eq!(entry.state_name(), "Empty");
        assert!(!entry.is_running());
    }

    #[test]
    fn empty_to_running() {
        let mut entry = CacheEntry::new();
        assert!(entry.start());
        assert_eq!(entry.state_name(), "Running");
        assert!(entry.is_running());
    }

    #[test]
    fn running_to_cached() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("hello".into(), HashMap::new());
        assert_eq!(entry.state_name(), "Cached");
        if let CacheEntry::Cached(c) = &entry {
            assert_eq!(c.value, "hello");
        } else {
            panic!("expected Cached");
        }
    }

    #[test]
    fn running_to_errored() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.fail("timeout".into());
        assert_eq!(entry.state_name(), "Errored");
        if let CacheEntry::Errored(e) = &entry {
            assert_eq!(e.error, "timeout");
            assert!(e.last_good_value.is_none());
        } else {
            panic!("expected Errored");
        }
    }

    #[test]
    fn cached_refresh_preserves_previous_value() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("v1".into(), HashMap::new());
        assert!(entry.start()); // Cached → Running
        assert!(entry.is_running());
        if let CacheEntry::Running(r) = &entry {
            assert_eq!(r.previous_value.as_deref(), Some("v1"));
        } else {
            panic!("expected Running");
        }
    }

    #[test]
    fn errored_retry_preserves_last_good() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("good".into(), HashMap::new());
        entry.start(); // Cached → Running (previous_value = "good")
        entry.fail("oops".into()); // Running → Errored (last_good_value = "good")
        if let CacheEntry::Errored(e) = &entry {
            assert_eq!(e.last_good_value.as_deref(), Some("good"));
        } else {
            panic!("expected Errored");
        }
        entry.start(); // Errored → Running
        if let CacheEntry::Running(r) = &entry {
            assert_eq!(r.previous_value.as_deref(), Some("good"));
        } else {
            panic!("expected Running");
        }
    }

    #[test]
    fn start_on_running_returns_false() {
        let mut entry = CacheEntry::new();
        entry.start();
        assert!(!entry.start()); // Already running
        assert!(entry.is_running());
    }

    #[test]
    fn complete_on_non_running_is_noop() {
        let mut entry = CacheEntry::new();
        entry.complete("ignored".into(), HashMap::new()); // Should be a no-op
        assert_eq!(entry.state_name(), "Empty");
    }

    #[test]
    fn expired_to_running() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("old".into(), HashMap::new());
        // Force expiry with zero max_age
        entry.check_expiry(Duration::ZERO);
        assert_eq!(entry.state_name(), "Expired");
        if let CacheEntry::Expired(e) = &entry {
            assert_eq!(e.last_value, "old");
        } else {
            panic!("expected Expired");
        }
        assert!(entry.start()); // Expired → Running
        if let CacheEntry::Running(r) = &entry {
            assert_eq!(r.previous_value.as_deref(), Some("old"));
        } else {
            panic!("expected Running");
        }
    }

    #[test]
    fn check_expiry_does_not_expire_fresh() {
        let mut entry = CacheEntry::new();
        entry.start();
        entry.complete("fresh".into(), HashMap::new());
        entry.check_expiry(Duration::from_secs(3600)); // 1 hour — won't expire
        assert_eq!(entry.state_name(), "Cached");
    }
}
