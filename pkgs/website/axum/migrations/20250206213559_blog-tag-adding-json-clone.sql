-- Add migration script here

ALTER TABLE blog_posts ADD COLUMN json_tags TEXT; -- Store tags as JSON array

