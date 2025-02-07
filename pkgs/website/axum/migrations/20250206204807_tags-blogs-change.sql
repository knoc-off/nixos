-- Add migration script here
ALTER TABLE blog_posts ADD COLUMN tags TEXT; -- Store tags as comma-separated string

