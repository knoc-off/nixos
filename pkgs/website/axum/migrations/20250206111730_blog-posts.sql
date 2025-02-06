-- Add migration script here

CREATE TABLE blog_posts (
    id TEXT PRIMARY KEY,  -- blog post ID (filename without extension)
    title TEXT NOT NULL,
    content TEXT NOT NULL, -- Full markdown content
    metadata TEXT NOT NULL, -- JSON blob of metadata
    checksum TEXT NOT NULL, -- Checksum of content + metadata
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_blog_posts_created_at ON blog_posts(created_at);
CREATE INDEX idx_blog_posts_tags ON blog_posts(metadata->'tags');
