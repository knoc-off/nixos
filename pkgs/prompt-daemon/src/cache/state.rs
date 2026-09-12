use std::collections::HashMap;
use tokio::time::Instant;

/// Initial state: key is known but no command has been executed yet.
#[derive(Debug)]
pub struct Empty;

/// A command is currently executing for this key.
#[derive(Debug)]
pub struct Running {
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
}

/// The command failed or timed out.
#[derive(Debug)]
pub struct Errored {
    pub error: String,
    pub last_good_value: Option<String>,
}
