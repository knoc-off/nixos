use std::collections::HashMap;
use tokio::time::Instant;

/// Initial state: key is known but no command has been executed yet.
#[derive(Debug)]
pub struct Empty;

/// A command is currently executing for this key.
#[derive(Debug)]
pub struct Running {
    pub since: Instant,
    pub previous_value: Option<String>,
}

/// Command completed successfully and the value is fresh.
#[derive(Debug)]
pub struct Cached {
    pub value: String,
    pub computed_at: Instant,
    pub env_snapshot: HashMap<String, String>,
}

/// The cached value has exceeded its `max_age`.
#[derive(Debug)]
pub struct Expired {
    pub last_value: String,
    pub computed_at: Instant,
}

/// The command failed or timed out.
#[derive(Debug)]
pub struct Errored {
    pub error: String,
    pub occurred_at: Instant,
    pub last_good_value: Option<String>,
}

// --- Typestate transitions ---
// Only valid transitions are defined. Invalid transitions are compile-time errors.

impl Empty {
    pub fn start(self) -> Running {
        Running {
            since: Instant::now(),
            previous_value: None,
        }
    }
}

impl Running {
    pub fn complete(self, value: String, env: HashMap<String, String>) -> Cached {
        Cached {
            value,
            computed_at: Instant::now(),
            env_snapshot: env,
        }
    }

    pub fn fail(self, error: String) -> Errored {
        Errored {
            error,
            occurred_at: Instant::now(),
            last_good_value: self.previous_value,
        }
    }
}

impl Cached {
    pub fn refresh(self) -> Running {
        Running {
            since: Instant::now(),
            previous_value: Some(self.value),
        }
    }

    pub fn expire(self) -> Expired {
        Expired {
            last_value: self.value,
            computed_at: self.computed_at,
        }
    }
}

impl Expired {
    pub fn retry(self) -> Running {
        Running {
            since: Instant::now(),
            previous_value: Some(self.last_value),
        }
    }
}

impl Errored {
    pub fn retry(self) -> Running {
        Running {
            since: Instant::now(),
            previous_value: self.last_good_value,
        }
    }
}
