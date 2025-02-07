-- Add migration script here
-- Drop existing tables (if they exist)
DROP TABLE IF EXISTS blog_posts;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS blog_post_tags;

-- Create the blog_posts table
CREATE TABLE blog_posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    content TEXT NOT NULL,
    metadata TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    cached_html TEXT
);

-- Create the tags table
CREATE TABLE tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

-- Create the blog_post_tags table (join table)
CREATE TABLE blog_post_tags (
    blog_post_id INTEGER NOT NULL,
    tag_id INTEGER NOT NULL,
    PRIMARY KEY (blog_post_id, tag_id),
    FOREIGN KEY (blog_post_id) REFERENCES blog_posts(id),
    FOREIGN KEY (tag_id) REFERENCES tags(id)
);

CREATE INDEX idx_blog_post_tags_blog_post_id ON blog_post_tags(blog_post_id);
CREATE INDEX idx_blog_post_tags_tag_id ON blog_post_tags(tag_id);

