-- Add migration script here

ALTER TABLE essay_submissions ADD COLUMN prompt_relevance INTEGER;
