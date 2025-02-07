-- Add migration script here
-- Drop the existing table (if it exists)
DROP TABLE IF EXISTS blog_posts;

CREATE TABLE blog_posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT, -- Auto-generated ID
    title TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE, -- URL-friendly slug
    content TEXT NOT NULL, -- Full markdown content
    metadata TEXT NOT NULL, -- JSON blob of metadata
    checksum TEXT NOT NULL, -- Checksum of content + metadata
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    cached_html TEXT
);

CREATE INDEX idx_blog_posts_created_at ON blog_posts(created_at);
CREATE INDEX idx_blog_posts_tags ON blog_posts(metadata->'tags');
CREATE INDEX idx_blog_posts_slug ON blog_posts(slug);

