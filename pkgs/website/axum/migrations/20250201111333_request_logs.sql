CREATE TABLE request_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    method TEXT NOT NULL,
    path TEXT NOT NULL,
    query_params TEXT,
    user_agent TEXT,
    referer TEXT,
    ip_address TEXT,
    host TEXT,
    duration_ms INTEGER NOT NULL,
    status_code INTEGER,
    content_type TEXT,
    accept_language TEXT,
    content_length INTEGER,
    is_mobile BOOLEAN,
    is_bot BOOLEAN
);

CREATE INDEX idx_request_logs_timestamp ON request_logs(timestamp);
CREATE INDEX idx_request_logs_path ON request_logs(path);
CREATE INDEX idx_request_logs_method ON request_logs(method);

