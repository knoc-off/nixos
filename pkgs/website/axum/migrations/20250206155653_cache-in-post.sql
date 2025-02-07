-- Add migration script here
ALTER TABLE blog_posts ADD COLUMN cached_html TEXT;
