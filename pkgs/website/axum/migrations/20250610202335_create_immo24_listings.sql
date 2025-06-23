-- In your ..._create_immo24_listings.sql file

-- Drop the old table if it exists, to ensure a clean slate on reset.
DROP TABLE IF EXISTS immo24_listings;

CREATE TABLE immo24_listings (
    -- === CORE QUERYABLE COLUMNS ===
    id                INTEGER PRIMARY KEY AUTOINCREMENT, -- Internal DB key
    scout_id          TEXT NOT NULL UNIQUE,              -- The external ID (e.g., "159753638")
    status            TEXT NOT NULL DEFAULT 'new',       -- User-managed status: 'new', 'saved', 'applied', 'rejected'
    total_rent        REAL,                              -- A key metric for sorting and filtering
    address           TEXT,                              -- For basic location searches
    published_at      DATETIME,                          -- For sorting by newest listings
    notes             TEXT,                              -- User-written notes

    -- === FLEXIBLE JSON COLUMNS ===
    -- We use TEXT to store JSON data in SQLite. sqlx handles the conversion.
    property_details  TEXT, -- JSON blob for: rent breakdown, floor, year, condition, etc.
    source_stats      TEXT, -- JSON blob for: views, saves, contacts
    contact_person    TEXT, -- JSON blob for: name, and future contact info
    text_descriptions TEXT, -- JSON blob for: object_description, location, etc.
    ai_insights       TEXT, -- JSON blob for: AI summary, amenities, etc.

    -- === TIMESTAMPS ===
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);



-- Create a trigger to automatically update the `updated_at` timestamp on any change.
-- This is a database best-practice.
CREATE TRIGGER update_immo24_listings_updated_at
AFTER UPDATE ON immo24_listings
FOR EACH ROW
BEGIN
    UPDATE immo24_listings SET updated_at = CURRENT_TIMESTAMP WHERE id = OLD.id;
END;
