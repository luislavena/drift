# Drift
> SQL-driven schema migration tool and library

Drift provides a framework-agnostic schema migration approach based on SQL
files. No magic DSL to learn, no weird ORM limitations to deal with, just
plain and simple SQL files in a folder, tracked and applied or reverted
(rollback) sequentially or in batches, and that's all.

> [!WARNING]
> Drift is still in **early development** and the UX/DX around the CLI and
> library/classes might change between versions.

## Features

* Self-contained migration files (both migrate and rollback statements within
  same `.sql` file).
* No new DSL or ORM to learn, just plain `.sql` files in a folder.
* A CLI to facilitate generation and execution of migrations.
* An optional library to be integrated within your project (Eg. to check and
  run migrations on start).
* Currently works with SQLite3, but can be adapted to be DB-agnostic,
  compatible with any [Crystal DB](https://github.com/crystal-lang/crystal-db)
  adapter.

## Overview

Drift aims to be a slim layer that orchestrates executing SQL statements
against a database. This applies to both [the CLI](#as-tool-cli) and
[the library](#as-library-crystal-shard) (Crystal shard).

Each migration file must contain two special comments before any SQL
statements: `drift:migrate` to indicate that the following statements should
be executed when migrating and `drift:rollback` to indicate the statements
should be executed when rolling back the migration.

Each type (migrate, rollback) within the file can contain multiple SQL
statements. Statements can span multiple lines, but all must be properly
terminated using `;`.

```sql
-- drift:migrate
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT,
  phone TEXT
);

-- drift:rollback
DROP TABLE IF EXISTS users;
```

Each migration must be identified by a unique ID. The recommended pattern for
this is to generate those IDs using dates and time. Eg. `20220601204500` as
ID translates to a migration created June 1st, 2022 at 8:45pm.

The CLI uses this convention when creating new migration files.

These migration files will be applied (migrate) one by one by executing each
of the SQL statements present on each migration.

Once completed, information about each applied migration will be stored within
the database itself, so can be used later to determine which one could be
rolled back, which ones were applied and when. All this information is
stored in a dedicated table named `drift_migrations`.

When rolling back, the applied migrations will be executed
in reverse order using the information on the previously mentioned table.

## Requirements

Drift CLI is a standalone, self-contained executable capable of connecting to
SQLite databases.

Drift (as library) only depends on Crystal's
[`db`](https://github.com/crystal-lang/crystal-db) common API. To use it with
to specific adapters, you need to add the respective dependencies and require
them part of your application. See more about in the
[library usage](#as-library-crystal-shard) section.

## Usage

### As tool (CLI)

Drift CLI can be used standalone of any framework or tool to manage the
structure of your database.

To simplify its usage, it follows these conventions:

* Migrations are stored and retrieved from `database/migrations` directory.
  This directory will be automatically created when creating your
  first migration.
* You can override this default by using `--path` option.
* To select which database to use, you can use `--db` option. The value for
  this must be a valid [connection URI](https://crystal-lang.org/reference/1.4/database/#open-database).
* If no option is provided, the CLI uses `DB_URL` environment variable
  instead.

#### Commands

To create a new migration:

```console
$ drift new CreateUsers
Created: database/migrations/20220601204500_create_users.sql
```

To apply the migrations:

```console
$ drift migrate --db sqlite3:app.db
Migrating: 20220601204500_create_users
Migrated:  20220601204500_create_users (10.31ms)
```

1. Drift looks at all of the migration files in your `database/migrations`
  directory.
2. It queries the `drift_migrations` table to see which migrations have and
  haven't been run.
3. Any migration that does not appear in the `drift_migrations` table is
  considered pending and is executed, as described in the
  [overview](#overview) section.

To verify which migrations were applied:

```console
$ drift status --db sqlite3:app.db
+--------------------------------------+------+-------+---------------------+----------+
| Migration                            | Ran? | Batch | Applied At          | Duration |
+--------------------------------------+------+-------+---------------------+----------+
| 20220601204500_create_users          | Yes  | 1     | 2022-06-01 20:49:13 |  10.31ms |
| 20220602123215_create_articles       |      |       |                     |          |
+--------------------------------------+------+-------+---------------------+----------+
```

Each time migrations are applied, a new *batch* is defined. This allow
rollback to revert all the migrations that were applied in a single batch.

```console
$ drift rollback
Rolling back: 20220601204500_create_users
Rolled back:  20220601204500_create_users (2.03ms)
```

While Drift doesn't offer a mechanism to drop your database and start from
zero, it offers a way to rollback all the migrations to it's original
state:

```console
$ drift reset
Rolling back: 20220602123215_create_articles
Rolled back:  20220602123215_create_articles (4.33ms)
Rolling back: 20220601204500_create_users
Rolled back:  20220601204500_create_users (2.03ms)
```

### As library (Crystal shard)

Outside of the CLI, you can streamline the usage of Drift as part of your
application:

```crystal
require "sqlite3"
require "drift"

db = DB.connect "sqlite3:app.db"

migrator = Drift::Migrator.from_path(db, "database/migrations")
migrator.apply!

db.close
```

The above is a simplified version of what happens when doing `drift migrate`
in the CLI. For example, you could apply these migrations as part of your
application start process.

Internally, the library interconnects the following elements:

A **migration** (`Drift::Migration`): represents each individual SQL file. It
contains all the SQL statements found within the SQL file that can be used to
apply or rollback the changes. Each migration must have a unique ID that
identifies itself, helping differentiate it from others and useful to keep
track and order of application.

The **context** (`Drift::Context`): represents a collection of migrations that
were loaded (parsed) from the filesystem, hardcoded or bundled within the
application. This is used as lookup table when mapping applied migration IDs
to the respective files.

The **migrator** (`Drift::Migrator`): in charge of orchestrating the
collection of migrations (context) against the database connection. To keep
track of the state changes (which migration were applied, when were applied),
the migrator uses a dedicated table named `drift_migrations` that is
automatically created if not found.

#### Embedding migrations

By default, Drift will load and use migration files from the filesystem. This
approach works great during development, but it increases complexity for
distribution of binaries.

To help with that, `Drift.embed_as` macro is available, which will collect
all the migration files from the filesystem and bundles them within the
generated executable, removing the need to distribute them along your
application.

```crystal
require "sqlite3"
require "drift"

Drift.embed_as("my_migrations", "database/migrations")

db = DB.connect "sqlite3:app.db"

migrator = Drift::Migrator.new(db, my_migrations)
migrator.apply!

db.close
```

In the above example, `Drift.embed_as` created `my_migrations` method
bundling all the migrations found in `database/migrations` directory.

When using classes or modules, you can also define instance or class methods
by prepending `self.` to the method name to use by Drift.

## Contribution policy

Inspired by [Litestream](https://github.com/benbjohnson/litestream) and
[SQLite](https://sqlite.org/copyright.html#notopencontrib), this project is
open to code contributions for bug fixes only. Features carry a long-term
burden so they will not be accepted at this time. Please
[submit an issue](https://github.com/luislavena/drift/issues/new) if you have
a feature you would like to request or discuss.

## License

Licensed under the Apache License, Version 2.0. You may obtain a copy of
the license [here](./LICENSE).
