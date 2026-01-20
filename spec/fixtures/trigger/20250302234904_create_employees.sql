-- drift:up
CREATE TABLE IF NOT EXISTS employees (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    position TEXT,
    salary REAL,
    hire_date DATE,
    last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- drift:down
DROP TABLE IF EXISTS employees;
