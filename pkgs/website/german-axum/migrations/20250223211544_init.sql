-- Add migration script here

CREATE TABLE IF NOT EXISTS text_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    original_text TEXT NOT NULL,
    annotated_text TEXT NOT NULL,  -- contains inline markup
    score REAL NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

