-- Add migration script here

-- This table will hold the global settings for the Immo24 feature.
-- We use `id` as a primary key and a CHECK constraint to ensure only one row ever exists.
CREATE TABLE immo24_settings (
    id INTEGER PRIMARY KEY NOT NULL DEFAULT 1,
    -- We will store the reasoning context as a JSON string.
    reasoning_context TEXT NOT NULL,
    -- The user's template for application messages.
    message_template TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
    CHECK (id = 1)
);

-- Insert the initial default settings so the GET endpoint works immediately.
INSERT INTO immo24_settings (reasoning_context, message_template) VALUES (
    '{"desired_features":["Balcony", "New Kitchen"],"dealbreaker_features":["Noisy Street"]}',
    'Sehr geehrte/r [Anbietername],\n\nich interessiere mich sehr für Ihre auf ImmobilienScout24 inserierte Wohnung unter der Scout-ID [Scout-ID].\n\n[Generierter Teil hier]\n\nIch würde mich über eine Einladung zu einem Besichtigungstermin sehr freuen.\n\nMit freundlichen Grüßen,\n[Ihr Name]'
);
