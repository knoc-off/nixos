use std::collections::HashMap;

use super::state::{Cached, Empty, Errored, Expired, Running};

/// Runtime wrapper enum over the typestate cache states.
/// Mediates transitions via match arms; the compiler enforces exhaustive handling.
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
