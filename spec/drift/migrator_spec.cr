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

# Each dialect is a development dependency and must be required so the
# connection pool can open the matching driver.
require "sqlite3"
require "mysql"

# Dialects exercised by the integration specs. Defaults target the compose
# services; override the URLs via the environment to point elsewhere.
DIALECTS = [
  {name: "SQLite3", url: ENV.fetch("SQLITE_URL", "sqlite3:%3Amemory%3A")},
  {name: "MySQL", url: ENV.fetch("MYSQL_URL", "mysql://root@mysql/drift_test")},
]

private def clean!(db)
  db.exec "DROP TABLE IF EXISTS dummy"
  db.exec "DROP TABLE IF EXISTS drift_migrations"
end

private def fresh_db(url)
  db = DB.connect(url)
  clean!(db)
  db
end

private def create_dummy(db)
  db.exec "CREATE TABLE IF NOT EXISTS dummy (value BIGINT NOT NULL);"
end

private def fake_migration(db, dialect, id = 1_i64, batch = 1_i64)
  db.transaction do |tx|
    dialect.record!(tx.connection, id, batch, Time.utc, 100_000_i64)
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

private def ready_migrator(url)
  Drift::Migrator.new(fresh_db(url), sample_context)
end

private def prepared_migrator(url)
  migrator = ready_migrator(url)
  migrator.prepare!
  {migrator.db, migrator}
end

DIALECTS.each do |dialect|
  url = dialect[:url]

  describe Drift::Migrator, "against #{dialect[:name]}" do
    describe ".new" do
      it "reuses an existing context" do
        ctx = sample_context
        migrator = Drift::Migrator.new(fresh_db(url), ctx)

        migrator.context.should be(ctx)
      end
    end

    describe ".from_path" do
      it "sets up a new context using a given path" do
        migrator = Drift::Migrator.from_path(fresh_db(url), fixture_path("sequence"))

        migrator.context.ids.should eq([
          20211219152312,
          20211220182717,
        ])
      end
    end

    describe "#prepared?" do
      it "returns false on a clean database" do
        migrator = ready_migrator(url)

        migrator.prepared?.should be_false
      end

      it "returns true on a prepared database" do
        db = fresh_db(url)
        db.exec "CREATE TABLE drift_migrations (id INTEGER PRIMARY KEY, dummy TEXT);"
        migrator = Drift::Migrator.new(db, sample_context)

        migrator.prepared?.should be_true
      end
    end

    describe "#prepare!" do
      it "prepares the migration table" do
        migrator = ready_migrator(url)

        migrator.prepare!
        migrator.db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
      end

      it "does noop if database is already prepared" do
        migrator = ready_migrator(url)

        migrator.prepare!
        migrator.prepare!
      end
    end

    describe "#applied?" do
      it "returns false when migration was not applied" do
        _, migrator = prepared_migrator(url)

        migrator.applied?(1).should be_false
      end

      it "returns true when migration was applied" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect

        migrator.applied?(1).should be_true
      end
    end

    describe "#applied_ids" do
      it "returns an empty list when no migrations were applied" do
        _, migrator = prepared_migrator(url)

        migrator.applied_ids.should be_empty
      end

      it "returns ordered list of applied migrations" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1
        fake_migration db, migrator.dialect, 2

        ids = migrator.applied_ids
        ids.should_not be_empty
        ids.should eq([1, 2])
      end

      it "returns only known applied migrations" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1
        fake_migration db, migrator.dialect, 5

        ids = migrator.applied_ids
        ids.should_not be_empty
        ids.should eq([1])
      end
    end

    describe "#apply_plan" do
      context "with no migration applied" do
        it "returns a list of all migrations" do
          _, migrator = prepared_migrator(url)

          ids = migrator.apply_plan
          ids.should_not be_empty
          ids.should eq([1, 2, 3, 4])
        end
      end

      context "with some applied migrations" do
        it "returns a list of non-applied migrations" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 3

          ids = migrator.apply_plan
          ids.should_not be_empty
          ids.should eq([2, 4])
        end
      end

      context "with applied migrations not locally available" do
        it "returns the list of only local non-applied ones" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 5

          ids = migrator.apply_plan
          ids.should eq([2, 3, 4])
        end
      end
    end

    describe "#apply(id)" do
      context "with no existing migrations applied" do
        it "records the migration was applied" do
          db, migrator = prepared_migrator(url)

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)

          entries = migrator.applied
          entry = entries.find { |e| e.id == 1 }
          entry.should_not be_nil
          entry = entry.not_nil!

          entry.id.should eq(1)
          entry.batch.should eq(1)
          entry.applied_at.should be_close(Time.utc, 1.second)
          entry.duration_ns.should be <= 1.second.total_nanoseconds.to_i64
        end

        it "applies migration only once" do
          db, migrator = prepared_migrator(url)
          migrator.apply(1)
          migrator.apply(1)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
        end

        it "executes migration statements" do
          db, migrator = prepared_migrator(url)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          migrator.apply(1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(1)
          db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(10)
        end

        it "applies migration within a transaction to avoid partial execution" do
          db, migrator = prepared_migrator(url)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")
          migration.add(:up, "INSERT INTO foo (value)")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.apply(1)
          end
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
        end
      end

      context "with existing migrations applied" do
        it "applies other migration as a new batch" do
          db, migrator = prepared_migrator(url)
          migrator.apply(1)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)

          migrator.apply(2)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
        end
      end
    end

    describe "#apply(ids)" do
      context "with no migrations" do
        it "applies multiple migrations as part of the same batch" do
          db, migrator = prepared_migrator(url)

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1, 3)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
        end

        it "ignores already applied migration from the list" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply(1, 3)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(2)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
        end

        it "increases batch number when executed multiple times for new migrations" do
          db, migrator = prepared_migrator(url)

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply(1, 2)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply(3, 4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
        end

        it "applies all migrations as transaction to avoid partial execution" do
          db, migrator = prepared_migrator(url)
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          m2 = migrator.context[3]
          m2.add(:up, "INSERT INTO dummy (value) VALUES (20);")
          m2.add(:up, "INSERT INTO foo (value)")

          expect_raises(Exception) do
            migrator.apply(1, 3)
          end
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
        end

        it "applies repeated migration in list only once" do
          db, migrator = prepared_migrator(url)
          create_dummy db

          migration = migrator.context[1]
          migration.add(:up, "INSERT INTO dummy (value) VALUES (10);")

          migrator.apply(1, 1, 1)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(1)
        end
      end
    end

    describe "#rollback(id)" do
      context "with migration applied" do
        it "removes migration from the list of applied" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.rollback(1)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
        end

        it "executes migration down statements" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(1)
        end

        it "removes only applied migrations" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect
          create_dummy db

          migration = migrator.context[2]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (20);")

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.rollback(2)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
        end

        it "applies rollback within a transaction to avoid partial execution" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          migration.add(:down, "INSERT INTO foo (value)")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.rollback(1)
          end
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(1)
        end
      end
    end

    describe "#rollback(ids)" do
      context "with no migrations applied" do
        it "does not rollback non-applied migration" do
          db, migrator = prepared_migrator(url)
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          m3 = migrator.context[3]
          m3.add(:down, "INSERT INTO dummy (value) VALUES (30);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(3, 1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
        end
      end

      context "with migrations applied" do
        it "removes migration from the list of applied" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 2

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(2)
          migrator.rollback(2, 1)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
        end

        it "considers migration only once" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          create_dummy db

          migration = migrator.context[1]
          migration.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(1, 1, 1, 1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(1)
        end

        it "executes migration down statements" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 2
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO dummy (value) VALUES (10);")
          m2 = migrator.context[2]
          m2.add(:down, "INSERT INTO dummy (value) VALUES (20);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          migrator.rollback(2, 1)
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(2)
          db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(20)
        end

        it "applies rollback within a transaction to avoid partial execution" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 2
          create_dummy db

          m1 = migrator.context[1]
          m1.add(:down, "INSERT INTO foo (value)")
          m2 = migrator.context[2]
          m2.add(:down, "INSERT INTO dummy (value) VALUES (10);")

          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          expect_raises(Exception) do
            migrator.rollback(2, 1)
          end
          db.scalar("SELECT COUNT(*) FROM dummy;").as(Int64).should eq(0)
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(2)
        end
      end
    end

    describe "#rollback_plan" do
      context "with no migration applied" do
        it "returns an empty list of migrations" do
          _, migrator = prepared_migrator(url)

          ids = migrator.rollback_plan
          ids.should be_empty
        end
      end

      context "dealing with batches" do
        it "returns the list of migrations in reverse order" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 2

          ids = migrator.rollback_plan
          ids.should_not be_empty
          ids.should eq([2, 1])
        end

        it "returns only the list of migrations in the last batch" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1, 1
          fake_migration db, migrator.dialect, 2, 1
          fake_migration db, migrator.dialect, 4, 2

          ids = migrator.rollback_plan
          ids.should_not be_empty
          ids.should eq([4])
        end
      end

      context "migrations not available locally" do
        it "excludes migrations not locally available" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 5

          ids = migrator.rollback_plan
          ids.should be_empty
        end
      end
    end

    describe "#reset_plan" do
      context "with no migration applied" do
        it "returns an empty list of migrations" do
          _, migrator = prepared_migrator(url)

          ids = migrator.reset_plan
          ids.should be_empty
        end
      end

      context "with a single batch" do
        it "returns a list of migrations in reverse order" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 3

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([3, 1])
        end

        it "excludes migrations not locally available" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 5

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([1])
        end
      end

      context "with multiple batches" do
        it "returns list of migrations in reverse order" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1, 1
          fake_migration db, migrator.dialect, 3, 1
          fake_migration db, migrator.dialect, 2, 2
          fake_migration db, migrator.dialect, 4, 2

          ids = migrator.reset_plan
          ids.should_not be_empty
          ids.should eq([4, 2, 3, 1])
        end
      end
    end

    describe "#pending?" do
      it "returns true when no migration was applied" do
        _, migrator = prepared_migrator(url)

        migrator.pending?.should be_true
      end

      it "returns false when all migrations were applied" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1
        fake_migration db, migrator.dialect, 2
        fake_migration db, migrator.dialect, 3
        fake_migration db, migrator.dialect, 4

        migrator.pending?.should be_false
      end
    end

    describe "#apply!" do
      context "with completely empty database" do
        it "prepares the migration table and applies migrations" do
          migrator = ready_migrator(url)

          migrator.apply!
          migrator.db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(4)
        end
      end

      context "with no existing migration applied" do
        it "applies all available migrations as single batch" do
          db, migrator = prepared_migrator(url)

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.apply!
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
        end
      end

      context "with existing batches" do
        it "applies pending migrations as new batch" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 3

          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
          migrator.apply!
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(4)
          db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
        end
      end
    end

    describe "#reset!" do
      context "with no migration applied" do
        it "does nothing" do
          db, migrator = prepared_migrator(url)

          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
          migrator.reset!
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
        end
      end

      context "with some applied migrations" do
        it "resets the migration status" do
          db, migrator = prepared_migrator(url)
          fake_migration db, migrator.dialect, 1
          fake_migration db, migrator.dialect, 3

          migrator.reset!
          db.scalar("SELECT COUNT(*) FROM drift_migrations;").as(Int64).should eq(0)
        end
      end
    end

    describe "(apply callback cycle)" do
      it "triggers before a migration is applied" do
        _, migrator = prepared_migrator(url)

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.apply(1)
        count.should eq(1)
      end

      it "triggers after a migration has been applied" do
        _, migrator = prepared_migrator(url)

        count = 0
        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.apply(1)
        count.should eq(1)
      end

      it "triggers callbacks in sequence" do
        _, migrator = prepared_migrator(url)

        events = Array(Symbol).new

        migrator.before_apply do |_|
          events.push :before
        end

        migrator.after_apply do |_, _|
          events.push :after
        end

        migrator.apply(1)
        events.should eq([:before, :after])
      end

      it "does not trigger if migration is already applied" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.apply(1)
        count.should eq(0)
      end
    end

    describe "(rollback callback cycle)" do
      it "triggers before a migration is rolled back" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1

        count = 0
        migrator.before_rollback do |_|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(1)
      end

      it "triggers after a migration has been rolled back" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1

        count = 0
        migrator.after_rollback do |_, _|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(1)
      end

      it "triggers callbacks in sequence" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1

        events = Array(Symbol).new
        migrator.before_rollback do |_|
          events.push :before
        end

        migrator.after_rollback do |_, _|
          events.push :after
        end

        migrator.rollback(1)
        events.should eq([:before, :after])
      end

      it "does not trigger if migration is not applied" do
        _, migrator = prepared_migrator(url)

        count = 0
        migrator.before_apply do |_|
          count += 1
        end

        migrator.after_apply do |_, _|
          count += 1
        end

        migrator.rollback(1)
        count.should eq(0)
      end

      it "resets in the right order" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1, 1
        fake_migration db, migrator.dialect, 3, 1
        fake_migration db, migrator.dialect, 2, 2
        fake_migration db, migrator.dialect, 4, 2

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
      end
    end

    describe "#applied" do
      it "returns an empty list when no migrations were applied" do
        _, migrator = prepared_migrator(url)

        migrator.applied.should be_empty
      end

      it "returns ordered list of applied migrations" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 1
        fake_migration db, migrator.dialect, 2

        entries = migrator.applied
        entries.should_not be_empty
        entries.size.should eq(2)

        mig1 = entries.first
        mig1.id.should eq(1)
      end

      it "returns only known applied migrations" do
        db, migrator = prepared_migrator(url)
        fake_migration db, migrator.dialect, 2
        fake_migration db, migrator.dialect, 5

        entries = migrator.applied
        entries.size.should eq(1)

        mig2 = entries.first
        mig2.id.should eq(2)
      end
    end
  end
end
