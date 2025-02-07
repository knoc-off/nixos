-- Add migration script here

-- Add a table to store the blog post counter
CREATE TABLE blog_post_counter (
    id INTEGER PRIMARY KEY CHECK (id = 1), -- Ensure only one row
    counter INTEGER NOT NULL DEFAULT 0
);

-- Initialize the counter
INSERT INTO blog_post_counter (id, counter) VALUES (1, 0);

