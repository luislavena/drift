-- drift:up
CREATE TABLE IF NOT EXISTS pets (
    id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    owner_id INTEGER NOT NULL,

    FOREIGN KEY(owner_id) REFERENCES humans(id) 
        ON UPDATE RESTRICT
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_pets_name ON pets(name);
CREATE INDEX IF NOT EXISTS idx_pets_owner ON pets(owner_id);

-- drift:down
DROP TABLE IF EXISTS pets;
