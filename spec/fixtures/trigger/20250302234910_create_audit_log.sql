-- drift:migrate
CREATE TABLE IF NOT EXISTS audit_log (
    id INTEGER PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (employee_id) REFERENCES employees (id)
);

-- drift:rollback
DROP TABLE IF EXISTS audit_log;
