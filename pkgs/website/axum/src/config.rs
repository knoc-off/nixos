// src/config.rs

use std::env;

/// Returns the database connection URL from the environment variables.
///
/// Panics if the `DATABASE_URL` environment variable is not set.
/// For local development, you can set this in a `.env` file.
/// Example: `DATABASE_URL=sqlite:db.sqlite?mode=rwc`
pub fn database_url() -> String {
    env::var("DATABASE_URL").expect("DATABASE_URL must be set")
}

/// Returns the path to the static content directory.
///
/// Defaults to "static" if the `STATIC_CONTENT_PATH` env var is not set.
pub fn static_content_path() -> String {
    env::var("STATIC_CONTENT_PATH").unwrap_or_else(|_| "static".to_string())
}
