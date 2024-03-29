-- drift:migrate
CREATE TABLE IF NOT EXISTS humans (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_humans_name ON humans(name);

-- drift:rollback
DROP INDEX IF EXISTS idx_humans_name;

DROP TABLE IF EXISTS humans;
