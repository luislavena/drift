-- drift:up
CREATE TABLE IF NOT EXISTS humans (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_humans_name ON humans(name);

-- drift:down
DROP TABLE IF EXISTS humans;
