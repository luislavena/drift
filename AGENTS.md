# AGENTS.md

Guidance for AI agents and contributors working on Drift.

## Project overview

Drift is a SQL-driven schema migration tool for Crystal. Framework-agnostic, works standalone (CLI) or as embedded library. Uses plain SQL files with migration markers instead of a DSL. Supports batch tracking for atomic rollback operations.

## Repository structure

```
src/
├── cli.cr                  # CLI entry point
├── drift.cr                # Main module and public API
└── drift/
    ├── migration.cr        # SQL parser
    ├── migrator.cr         # Migration orchestrator
    ├── context.cr          # Migration collection manager
    ├── dialect.cr          # Dialect base class + selection (from_db)
    ├── dialects/           # Per-engine SQL (sqlite3, mysql, postgresql)
    ├── migration_entry.cr  # Applied migration record
    ├── embed.cr            # Macro for embedding migrations
    ├── commands/           # CLI commands (migrate, rollback, reset, status, new, version)
    └── support/migrations_loader.cr

spec/                       # Tests (spec_helper.cr, drift_spec.cr, drift/*_spec.cr)
```

## Core components

**Migration** (`src/drift/migration.cr`): Parses SQL files with markers:

```sql
-- drift:up
CREATE TABLE users (id INTEGER PRIMARY KEY);

-- drift:down
DROP TABLE users;
```

Multi-statement blocks use `-- drift:begin` and `-- drift:end`.

**Context** (`src/drift/context.cr`): Manages migration collection with lazy-loading and hash-like access.

**Migrator** (`src/drift/migrator.cr`): Orchestrates migrations against database, manages `drift_migrations` table, supports callbacks.

## Development

Requires: Crystal >= 1.4.0, < 2.0.0 | SQLite3 dev libs | Docker

```bash
make setup      # Initialize and install dependencies
make dev        # Start with hot reload
make console    # Interactive session
make stop       # Stop containers
```

All commands run in container via `docker compose run --rm app --`:

```bash
# Build
shards build drift              # Debug
shards build --release drift    # Release (outputs to bin/drift)

# Test
crystal spec                           # All tests
crystal spec spec/drift/migration_spec.cr  # Specific file
crystal spec --verbose                 # Verbose

# Cross-engine specs (MySQL/PostgreSQL) skip unless these are set. The app
# container in compose.yaml sets them already; from the host:
docker compose up -d mysql postgres
export MYSQL_DATABASE_URL="mysql://root:drift@127.0.0.1:3306/drift_test"
export POSTGRES_DATABASE_URL="postgres://postgres:drift@127.0.0.1:5432/drift_test"

# Format (enforced by CI)
crystal tool format src/ spec/         # Apply
crystal tool format --check src/ spec/ # Check only
```

## Pull request guidelines

**Branch naming:** Use dashes, not slashes (`feature-add-postgres-support`).

**Changelog:** Required for every PR (use `changie`):

```bash
changie new --kind <kind> --body "<description>" [--custom issue=N]
```

Kinds: `added`, `improved`, `changed`, `deprecated`, `removed`, `fixed`, `security`, `internal`

**Commits:** Imperative mood, 50-char subject, 72-char body wrap. Explain what/why, not how.

**Before submitting:**
1. Tests pass
2. Code formatted
3. Changelog entry added
4. Rebased on main

**CI checks:** Format, tests, changelog.

## Contribution policy

- Bug fixes welcome via PR
- New features require GitHub issue discussion first
- Database adapters welcome but discuss first
