-- Add migration script here
-- migrations/YYYYMMDDHHMMSS_create_immo24_listings.sql
CREATE TABLE listings (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    scout_id          TEXT NOT NULL UNIQUE,
    url               TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'new',
    notes             TEXT,
    -- JSONB is a PostgreSQL type. For SQLite, we use TEXT and handle JSON manually.
    -- sqlx's `Json<T>` feature handles this seamlessly for us.
    property_data     TEXT,
    ai_insights       TEXT,
    processing_status TEXT NOT NULL DEFAULT 'pending',
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
