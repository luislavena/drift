# Copyright 2022 Luis Lavena
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "../spec_helper"

require "mysql"
require "pg"
require "sqlite3"

# Configuration for dialects to test
DIALECTS = {
  sqlite3: {
    url:           ENV["SQLITE3_DB_URL"]? || "sqlite3:%3Amemory%3A",
    needs_cleanup: false,
  },
  postgresql: {
    url:           ENV["POSTGRES_DB_URL"]? || "postgres://drift:drift@localhost:5432/drift_test",
    needs_cleanup: true,
  },
  mysql: {
    url:           ENV["MYSQL_DB_URL"]? || "mysql://drift:drift@localhost:3306/drift_test",
    needs_cleanup: true,
  },
}

private struct MigrationEntry
  include DB::Serializable

  getter id : Int64
  getter batch : Int64
  getter applied_at : Time
  getter duration_ns : Int64
end

private def memory_db
  DB.open "sqlite3:%3Amemory%3A"
end

private def create_dummy(db)
  case Drift::Dialect.from_db(db)
  when Drift::Dialect::SQLite3
    db.exec("CREATE TABLE IF NOT EXISTS dummy (id INTEGER PRIMARY KEY NOT NULL, value INTEGER NOT NULL);")
  when Drift::Dialect::PostgreSQL
    db.exec("CREATE TABLE IF NOT EXISTS dummy (id BIGSERIAL PRIMARY KEY NOT NULL, value BIGINT NOT NULL);")
  when Drift::Dialect::MySQL
    db.exec("CREATE TABLE IF NOT EXISTS dummy (id BIGINT PRIMARY KEY AUTO_INCREMENT NOT NULL, value BIGINT NOT NULL);")
  end
end

private def fake_migration(db, id = 1, batch = 1)
  case Drift::Dialect.from_db(db)
  when Drift::Dialect::SQLite3, Drift::Dialect::MySQL
    db.exec("INSERT INTO drift_migrations (id, batch, applied_at, duration_ns) VALUES (?, ?, ?, ?);", id, batch, Time.utc, 100000)
  when Drift::Dialect::PostgreSQL
    db.exec("INSERT INTO drift_migrations (id, batch, applied_at, duration_ns) VALUES ($1, $2, $3, $4);", id, batch, Time.utc, 100000)
  end
end

private def sample_context
  ctx = Drift::Context.new

  ctx.add Drift::Migration.new(1)
  ctx.add Drift::Migration.new(2)
  ctx.add Drift::Migration.new(3)
  ctx.add Drift::Migration.new(4)

  ctx
end

private def cleanup_tables(db)
  db.exec("DROP TABLE IF EXISTS drift_migrations CASCADE;")
  db.exec("DROP TABLE IF EXISTS dummy CASCADE;")
end

private def ready_migrator(db)
  ctx = sample_context
  migrator = Drift::Migrator.new(db, ctx)

  migrator
end

private def prepared_migrator(db)
  migrator = ready_migrator(db)
  migrator.prepare!

  {db, migrator}
end

# Macro to run tests for each dialect
macro for_each_dialect
  {% for name, config in DIALECTS %}
    {% skip_postgresql = env("SKIP_POSTGRESQL") == "true" %}
    {% skip_mysql = env("SKIP_MYSQL") == "true" %}
    {% unless (name.id == "postgresql" && skip_postgresql) || (name.id == "mysql" && skip_mysql) %}
      describe "with {{ name.id }}" do
        # Proc to get a clean DB connection for this dialect
        dialect_db = ->() {
          db = DB.open({{ config[:url] }})
          {% if config[:needs_cleanup] %}
            cleanup_tables(db)
          {% end %}
          db
        }

        {{ yield }}
      end
    {% end %}
  {% end %}
end

describe Drift::Migrator do
  describe ".new" do
    it "reuses an existing context" do
      db = memory_db
      ctx = sample_context
      migrator = Drift::Migrator.new(db, ctx)

      migrator.context.should be(ctx)

      db.close
    end
  end

  describe ".from_path" do
    it "sets up a new context using a given path" do
      db = memory_db
      migrator = Drift::Migrator.from_path(db, fixture_path("sequence"))

      migrator.context.ids.should eq([
        20211219152312,
        20211220182717,
      ])

      db.close
    end
  end

  for_each_dialect do
    describe "#prepared?" do
      it "returns false on an clean database" do
        db = dialect_db.call
        migrator = ready_migrator(db)

        migrator.prepared?.should be_false

        db.close
      end

      it "returns true on a prepared database" do
        db = dialect_db.call
        # dummy table
        db.exec "CREATE TABLE drift_migrations (id INTEGER PRIMARY KEY, dummy TEXT);"
        migrator = ready_migrator(db)

        migrator.prepared?.should be_true

        db.close
      end
    end

    describe "#prepare!" do
      it "prepares the migration table" do
        db = dialect_db.call
        migrator = ready_migrator(db)

        migrator.prepare!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

        db.close
      end

      it "does noop if database is already prepared" do
        db = dialect_db.call
        migrator = ready_migrator(db)

        migrator.prepare!
        migrator.prepare!

        db.close
      end
    end
  end

  for_each_dialect do
    describe "#applied?" do
      it "returns false when migration was not applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        migrator.applied?(1).should be_false

        db.close
      end

      it "returns true when migration was applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db

        migrator.applied?(1).should be_true

        db.close
      end
    end

    describe "#applied_ids" do
      it "returns an empty list when no migrations were applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        migrator.applied_ids.should be_empty

        db.close
      end

      it "returns ordered list of applied migrations" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1
        fake_migration db, 2

        ids = migrator.applied_ids
        ids.should_not be_empty
        ids.should eq([1, 2])

        db.close
      end

      it "returns only known applied migrations" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1
        fake_migration db, 5

        ids = migrator.applied_ids
        ids.should_not be_empty
        ids.should eq([1])

        db.close
      end
    end
  end

  for_each_dialect do
    describe "#apply_plan" do
      context "with no migration applied" do
        it "returns a list of all migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          ids = migrator.apply_plan
          ids.should_not be_empty
          ids.should eq([1, 2, 3, 4])

          db.close
        end
      end

      context "with some applied migrations" do
        it "returns a list of non-applied migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 3

          ids = migrator.apply_plan
          ids.should_not be_empty
          ids.should eq([2, 4])

          db.close
        end
      end

      context "with applied migrations not locally available" do
        it "returns the list of only local non-applied ones" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 5

          ids = migrator.apply_plan
          ids.should eq([2, 3, 4])

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#apply(id)" do
      context "with no existing migrations applied" do
        it "records the migration was applied" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)

          # id, batch, applied_at, duration_ns
          result = db.query_one("SELECT id, batch, applied_at, duration_ns FROM drift_migrations ORDER BY id ASC LIMIT 1;", as: MigrationEntry)

          result.id.should eq(1)
          result.batch.should eq(1)
          result.applied_at.should be_close(Time.utc, 1.second)
          result.duration_ns.should be <= 1.second.total_nanoseconds.to_i64

          db.close
        end

        it "applies migration only once" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          migrator.apply(1)
          migrator.apply(1)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)

          db.close
        end

        it "executes migration statements" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          migrator.apply(1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)
          db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(10)

          db.close
        end

        it "applies migration within a transaction to avoid partial execution" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")
          migration.add(:up, "INSERT INTO foo (value);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.apply(1)
          end
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

          db.close
        end
      end

      context "with existing migrations applied" do
        it "applies other migration as a new batch" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          migrator.apply(1)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)

          migrator.apply(2)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#apply(ids)" do
      context "with no migrations" do
        it "applies multiple migrations as part of the same batch" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1, 3)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)

          db.close
        end

        it "ignores already applied migration from the list" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply(1, 3)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)

          db.close
        end

        it "increases batch number when executed multiple times for new migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1, 2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply(3, 4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)

          db.close
        end

        it "applies all migrations as transaction to avoid partial execution" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          m2 = migrator.context[3]
          m2.add(:up, "INSERT INTO dummy (value) VALUES (20);")
          m2.add(:up, "INSERT INTO foo (value)")

          expect_raises(Exception) do
            migrator.apply(1, 3)
          end
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)

          db.close
        end

        it "applies repeated migration in list only once" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          migrator.apply(1, 1, 1)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#rollback(id)" do
      context "with migration applied" do
        it "removes migration from the list of applied" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.rollback(1)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

          db.close
        end

        it "executes migration down statements" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)

          db.close
        end

        it "removes only applied migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db
          create_dummy db

          migration = migrator.context[2]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (20);")

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.rollback(2)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)

          db.close
        end

        it "applies rollback within a transaction to avoid partial execution" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          migration.add(:down, "INSERT INTO foo (value);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.rollback(1)
          end
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#rollback(ids)" do
      context "with no migrations applied" do
        it "does not rollback non-applied migration" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          m3 = migrator.context[3]
          m3.add(:down, "INSERT INTO dummy (value) VALUES (30);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(3, 1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)

          db.close
        end
      end

      context "with migrations applied" do
        it "removes migration from the list of applied" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 2

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
          migrator.rollback(2, 1)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

          db.close
        end

        it "considers migration only once" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(1, 1, 1, 1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)

          db.close
        end

        it "executes migration down statements" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 2
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          m2 = migrator.context[2]
          m2.add(:down, "INSERT INTO dummy (value) VALUES (20);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(2, 1)
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(20)

          db.close
        end

        it "applies rollback within a transaction to avoid partial execution" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 2
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO foo (value);")
          m2 = migrator.context[2]
          m2.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.rollback(2, 1)
          end
          db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#rollback_plan" do
      context "with no migration applied" do
        it "returns an empty list of migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          ids = migrator.rollback_plan
          ids.should be_empty

          db.close
        end
      end

      context "dealing with batches" do
        it "returns the list of migrations in reverse order" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 2

          ids = migrator.rollback_plan
          ids.should_not be_empty
          ids.should eq([2, 1])

          db.close
        end

        it "returns only the list of migrations in the last batch" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1, 1
          fake_migration db, 2, 1
          fake_migration db, 4, 2

          ids = migrator.rollback_plan
          ids.should_not be_empty
          ids.should eq([4])

          db.close
        end
      end

      context "migrations not available locally" do
        it "excludes migrations not locally available" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 5

          ids = migrator.rollback_plan
          ids.should be_empty

          db.close
        end
      end
    end

    describe "#reset_plan" do
      context "with no migration applied" do
        it "returns an empty list of migrations" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          ids = migrator.reset_plan
          ids.should be_empty

          db.close
        end
      end

      context "with a single batch" do
        it "returns a list of migrations in reverse order" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 3

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([3, 1])

          db.close
        end

        it "excludes migrations not locally available" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 5

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([1])

          db.close
        end
      end

      context "with multiple batches" do
        it "returns list of migrations in reverse order" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1, 1
          fake_migration db, 3, 1
          fake_migration db, 2, 2
          fake_migration db, 4, 2

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([4, 2, 3, 1])

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "#pending?" do
      it "returns true when no migration was applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        migrator.pending?.should be_true

        db.close
      end

      it "returns false when all migrations were applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1
        fake_migration db, 2
        fake_migration db, 3
        fake_migration db, 4

        migrator.pending?.should be_false

        db.close
      end
    end

    describe "#apply!" do
      context "with completely empty database" do
        it "prepares the migration table and applies migrations" do
          db = dialect_db.call
          migrator = ready_migrator(db)

          migrator.apply!
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)

          db.close
        end
      end

      context "with no existing migration applied" do
        it "applies all available migrations as single batch" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply!
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)

          db.close
        end
      end

      context "with existing batches" do
        it "applies pending migrations as new batch" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 3

          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply!
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)

          db.close
        end
      end
    end

    describe "#reset!" do
      context "with no migration applied" do
        it "does nothing" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)

          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.reset!
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

          db.close
        end
      end

      context "with some applied migrations" do
        it "resets the migration status" do
          db = dialect_db.call
          _, migrator = prepared_migrator(db)
          fake_migration db, 1
          fake_migration db, 3

          migrator.reset!
          db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)

          db.close
        end
      end
    end
  end

  for_each_dialect do
    describe "(apply callback cycle)" do
      it "triggers before a migration is applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.apply(1)
        count.should eq(1)

        db.close
      end

      it "triggers after a migration has been applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        count = 0
        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.apply(1)
        count.should eq(1)

        db.close
      end

      it "triggers callbacks in sequence" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        events = Array(Symbol).new

        migrator.before_apply do |_|
          events.push :before
        end

        migrator.after_apply do |_, _|
          events.push :after
        end

        migrator.apply(1)
        events.should eq([:before, :after])

        db.close
      end

      it "does not trigger if migration is already applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.apply(1)
        count.should eq(0)

        db.close
      end
    end

    describe "(rollback callback cycle)" do
      it "triggers before a migration is rolled back" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1

        count = 0
        migrator.before_rollback do |_|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(1)

        db.close
      end

      it "triggers after a migration has been rolled back" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1

        count = 0
        migrator.after_rollback do |_, _|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(1)

        db.close
      end

      it "triggers callbacks in sequence" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1

        events = Array(Symbol).new
        migrator.before_rollback do |_|
          events.push :before
        end

        migrator.after_rollback do |_, _|
          events.push :after
        end

        migrator.rollback(1)
        events.should eq([:before, :after])

        db.close
      end

      it "does not trigger if migration is not applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(0)

        db.close
      end

      it "resets in the right order" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1, 1
        fake_migration db, 3, 1
        fake_migration db, 2, 2
        fake_migration db, 4, 2

        before_ids = Array(Int64).new
        migrator.before_rollback do |id|
          before_ids.push id
        end

        after_ids = Array(Int64).new
        migrator.after_rollback do |id, _|
          after_ids.push id
        end

        migrator.reset!
        before_ids.size.should eq(4)
        after_ids.size.should eq(4)
        before_ids.should eq([4, 2, 3, 1])
        after_ids.should eq([4, 2, 3, 1])

        db.close
      end
    end
  end

  for_each_dialect do
    describe "#applied" do
      it "returns an empty list when no migrations were applied" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)

        migrator.applied.should be_empty

        db.close
      end

      it "returns ordered list of applied migrations" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 1
        fake_migration db, 2

        entries = migrator.applied
        entries.should_not be_empty
        entries.size.should eq(2)

        mig1 = entries.first
        mig1.id.should eq(1)

        db.close
      end

      it "returns only known applied migrations" do
        db = dialect_db.call
        _, migrator = prepared_migrator(db)
        fake_migration db, 2
        fake_migration db, 5

        entries = migrator.applied
        entries.size.should eq(1)

        mig2 = entries.first
        mig2.id.should eq(2)

        db.close
      end
    end
  end
end
