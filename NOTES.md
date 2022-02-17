# Drift

## Library DX

A migration can contain multiple statements on each direction:

```crystal
migration = Drift::Migration.new(1)
migration.add(:up, <<-SQL)
    CREATE TABLE IF NOT EXISTS pets
    (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        ...
    );
    SQL

migration.add(:up, "CREATE INDEX idx_pets_name ON pets(name);")

migration.add(:down, <<-SQL)
    DROP TABLE IF EXISTS pets;
    SQL
```

**Note**: All the statements given for a direction (Eg. Up or Down) will be
wrapped in a transaction when executed by `Drift::Conductor`

```crystal
db = DB.open "..." # or DB.connect
conductor = Drift::Conductor.new

# add migrations manually
migration = Drift::Migration.new(1, "0001_create_users.sql")
conductor.add migration

# load from a folder (*.sql)
conductor.load_migrations "/path/to/migrations"
```

---

A single migration, read from a file:

```crystal
migration = Drift::Migration.from_file("db/migrations/20211220173103_create_users_table.sql")
```

Manually create a migration:

```crystal
migration = Drift::Migration.new(20211220173103)
migration.statements_for(:up).push <<-SQL
    CREATE TABLE IF NOT EXISTS foo
    (
        id INTEGER PRIMARY KEY,
        ...
    );
    SQL

migration.statements_for(:down).push <<-SQL
    DROP TABLE IF EXISTS foo;
    SQL
```

Initialize a Migrator:

```crystal
migrator = Drift::Conductor.new
```

Run migration against a DB:

```crystal
db = DB.connect("...")

migration.up(db)
migration.ran?(db) # => true
migration.applied_at?(db) # => Time

migration.down(db)
migration.ran?(db) # => false
migration.applied_at?(db) # => nil
```

Load migration from file(s):

```crystal
migration = Drift::Migration.from_file("db/migrations/20211220173103_create_users_table.sql")
```

## CLI UX

```console
$ drift new create_users_table
    YYYYMMDDHHMMSS_create_users_table.sql
```

```console
$ drift migrate
```

```console
$ drift status

Migration | Ran? | Batch | Applied At

+------+----------------------------------------------------------------+-------+
| Ran? | Migration                                                      | Batch | Applied At
+------+----------------------------------------------------------------+-------+
| Yes  | 20141012000000_create_users_table                              | 1     |
```

```console
drift rollback
drift rollback --batch=N

drift redo --batch=N
```
