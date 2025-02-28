-- Add migration script here
ALTER TABLE essay_submissions
ADD COLUMN annotated_text TEXT;

