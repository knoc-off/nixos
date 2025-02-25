-- Add migration script here

INSERT INTO users (login_name, password_hash, email, overall_score)
VALUES ('test', 'secret', 'test@example.com', 0)
ON CONFLICT(login_name) DO NOTHING;

