-- Add migration script here

-- ./migrations/20240101000001_easis.sql
CREATE TABLE IF NOT EXISTS essay_prompts (
    id INTEGER PRIMARY KEY NOT NULL,
    topic TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS essay_submissions (
    id INTEGER PRIMARY KEY NOT NULL,
    user_id INTEGER NOT NULL,
    prompt_id INTEGER NOT NULL,
    original_text TEXT NOT NULL,
    corrected_text TEXT,
    score INTEGER,
    error_count INTEGER,
    submitted_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (prompt_id) REFERENCES essay_prompts(id)
);

-- Add some sample prompts
INSERT INTO essay_prompts (topic) VALUES
('What would you do if you could travel anywhere in the world?'),
('How has technology changed our daily lives in the past decade?'),
('What do you think is the most important invention in human history?');
