-- Add migration script here

-- Create the my_table table
CREATE TABLE my_table (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL
);

-- Insert some sample data
INSERT INTO my_table (name) VALUES ('Test Item 1');
INSERT INTO my_table (name) VALUES ('Test Item 2');
INSERT INTO my_table (name) VALUES ('Test Item 3');
