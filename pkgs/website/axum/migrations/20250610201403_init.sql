-- Add migration script here
-- This is the table your logger middleware needs.
-- It should be in your `..._create_request_logs.sql` migration file.
CREATE TABLE IF NOT EXISTS request_logs (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp   DATETIME DEFAULT CURRENT_TIMESTAMP,
    method      TEXT NOT NULL,
    uri         TEXT NOT NULL, -- This is the column that was missing.
    status_code INTEGER NOT NULL,
    latency_ms  INTEGER NOT NULL
);

-- This table is created and managed automatically by `sqlx-cli`.
-- You do NOT need to create this yourself.
-- It tracks the version of the database.
CREATE TABLE IF NOT EXISTS _sqlx_migrations (
    version BIGINT PRIMARY KEY,
    description TEXT NOT NULL,
    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN NOT NULL,
    checksum BLOB NOT NULL,
    execution_time BIGINT NOT NULL
);
