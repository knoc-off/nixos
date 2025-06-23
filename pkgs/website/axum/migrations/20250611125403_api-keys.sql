-- Add migration script here
-- migrations/YYYYMMDDHHMMSS_create_api_keys.sql
CREATE TABLE IF NOT EXISTS api_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    key TEXT NOT NULL UNIQUE,
    description TEXT,
    -- We can add permissions later, e.g., a 'permissions' TEXT column
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Insert a test key so we can use it immediately
INSERT INTO api_keys (key, description) VALUES ('my-secret-key-123', 'Test key for immo24');
