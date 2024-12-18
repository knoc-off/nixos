-- Add migration script here

-- Drop the existing table
DROP TABLE IF EXISTS my_table;

-- Recreate the table with the unique constraint on 'name'
CREATE TABLE my_table (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
);

