-- Add migration script here
ALTER TABLE immo24_listings ADD COLUMN processing_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE immo24_listings ADD COLUMN processing_error TEXT;
