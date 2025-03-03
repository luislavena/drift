-- drift:migrate
-- drift:begin
CREATE TRIGGER update_timestamp AFTER
UPDATE ON employees BEGIN
UPDATE employees
SET
    last_modified = CURRENT_TIMESTAMP
WHERE
    id = NEW.id;

INSERT INTO
    audit_log (employee_id, action)
VALUES
    (NEW.id, 'updated');

END;
-- drift:end

-- drift:rollback
DROP TRIGGER IF EXISTS update_timestamp;
