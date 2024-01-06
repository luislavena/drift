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

require "sqlite3"

private struct MigrationEntry
  include DB::Serializable

  getter id : Int64
  getter batch : Int64
  getter applied_at : Time
  getter duration_ns : Int64
end

private def memory_db
  DB.connect "sqlite3:%3Amemory%3A"
end

private def create_dummy(db)
  db.exec("CREATE TABLE IF NOT EXISTS dummy (id INTEGER PRIMARY KEY NOT NULL, value INTEGER NOT NULL);")
end

private def fake_migration(db, id = 1, batch = 1)
  db.exec("INSERT INTO drift_migrations (id, batch, applied_at, duration_ns) VALUES (?, ?, ?, ?);", id, batch, Time.utc, 100000)
end

private def sample_context
  ctx = Drift::Context.new

  ctx.add Drift::Migration.new(1)
  ctx.add Drift::Migration.new(2)
  ctx.add Drift::Migration.new(3)
  ctx.add Drift::Migration.new(4)

  ctx
end

private def ready_migrator(db = memory_db)
  ctx = sample_context
  migrator = Drift::Migrator.new(db, ctx)

  migrator
end

private def prepared_migrator
  db = memory_db
  migrator = ready_migrator(db)
  migrator.prepare!

  {db, migrator}
end

describe Drift::Migrator do
  describe ".new" do
    it "reuses an existing context" do
      ctx = sample_context
      migrator = Drift::Migrator.new(memory_db, ctx)

      migrator.context.should be(ctx)
    end
  end

  describe ".from_path" do
    it "sets up a new context using a given path" do
      migrator = Drift::Migrator.from_path(memory_db, fixture_path("sequence"))

      migrator.context.ids.should eq([
        20211219152312,
        20211220182717,
      ])
    end
  end

  describe "#prepared?" do
    it "returns false on an clean database" do
      migrator = ready_migrator

      migrator.prepared?.should be_false
    end

    it "returns true on a prepared database" do
      db = memory_db
      # dummy table
      db.exec "CREATE TABLE drift_migrations (id INTEGER PRIMARY KEY, dummy TEXT);"
      migrator = ready_migrator(db)

      migrator.prepared?.should be_true
    end
  end

  describe "#prepare!" do
    it "prepares the migration table" do
      db = memory_db
      migrator = ready_migrator(db)

      migrator.prepare!
      db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
    end

    it "does noop if database is already prepared" do
      migrator = ready_migrator

      migrator.prepare!
      migrator.prepare!
    end
  end

  describe "#applied?" do
    it "returns false when migration was not applied" do
      _, migrator = prepared_migrator

      migrator.applied?(1).should be_false
    end

    it "returns true when migration was applied" do
      db, migrator = prepared_migrator
      fake_migration db

      migrator.applied?(1).should be_true
    end
  end

  describe "#applied_ids" do
    it "returns an empty list when no migrations were applied" do
      _, migrator = prepared_migrator

      migrator.applied_ids.should be_empty
    end

    it "returns ordered list of applied migrations" do
      db, migrator = prepared_migrator
      fake_migration db, 1
      fake_migration db, 2

      ids = migrator.applied_ids
      ids.should_not be_empty
      ids.should eq([1, 2])
    end

    it "returns only known applied migrations" do
      db, migrator = prepared_migrator
      fake_migration db, 1
      fake_migration db, 5

      ids = migrator.applied_ids
      ids.should_not be_empty
      ids.should eq([1])
    end
  end

  describe "#apply_plan" do
    context "with no migration applied" do
      it "returns a list of all migrations" do
        _, migrator = prepared_migrator

        ids = migrator.apply_plan
        ids.should_not be_empty
        ids.should eq([1, 2, 3, 4])
      end
    end

    context "with some applied migrations" do
      it "returns a list of non-applied migrations" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 3

        ids = migrator.apply_plan
        ids.should_not be_empty
        ids.should eq([2, 4])
      end
    end

    context "with applied migrations not locally available" do
      it "returns the list of only local non-applied ones" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 5

        ids = migrator.apply_plan
        ids.should eq([2, 3, 4])
      end
    end
  end

  describe "#apply(id)" do
    context "with no existing migrations applied" do
      it "records the migration was applied" do
        db, migrator = prepared_migrator

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        migrator.apply(1)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)

        # id, batch, applied_at, duration_ns
        result = db.query_one("SELECT id, batch, applied_at, duration_ns FROM drift_migrations WHERE id = ? LIMIT 1;", 1, as: MigrationEntry)

        result.id.should eq(1)
        result.batch.should eq(1)
        result.applied_at.should be_close(Time.utc, 1.second)
        result.duration_ns.should be <= 1.second.total_nanoseconds.to_i64
      end

      it "applies migration only once" do
        db, migrator = prepared_migrator
        migrator.apply(1)
        migrator.apply(1)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
      end

      it "executes migration statements" do
        db, migrator = prepared_migrator
        create_dummy db

        migration = migrator.context[1]
        migration.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        migrator.apply(1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)
        db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(10)
      end

      it "applies migration within a transaction to avoid partial execution" do
        db, migrator = prepared_migrator
        create_dummy db

        migration = migrator.context[1]
        migration.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")
        migration.add(:migrate, "INSERT INTO foo (value)")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        expect_raises(Exception) do
          migrator.apply(1)
        end
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
      end
    end

    context "with existing migrations applied" do
      it "applies other migration as a new batch" do
        db, migrator = prepared_migrator
        migrator.apply(1)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)

        migrator.apply(2)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
      end
    end
  end

  describe "#apply(ids)" do
    context "with no migrations" do
      it "applies multiple migrations as part of the same batch" do
        db, migrator = prepared_migrator

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        migrator.apply(1, 3)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
      end

      it "ignores already applied migration from the list" do
        db, migrator = prepared_migrator
        fake_migration db
        create_dummy db

        m1 = migrator.context[1]
        m1.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
        migrator.apply(1, 3)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
      end

      it "increases batch number when executed multiple times for new migrations" do
        db, migrator = prepared_migrator

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        migrator.apply(1, 2)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
        migrator.apply(3, 4)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
      end

      it "applies all migrations as transaction to avoid partial execution" do
        db, migrator = prepared_migrator
        create_dummy db

        m1 = migrator.context[1]
        m1.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")

        m2 = migrator.context[3]
        m2.add(:migrate, "INSERT INTO dummy (value) VALUES (20);")
        m2.add(:migrate, "INSERT INTO foo (value)")

        expect_raises(Exception) do
          migrator.apply(1, 3)
        end
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
      end

      it "applies repeated migration in list only once" do
        db, migrator = prepared_migrator
        create_dummy db

        migration = migrator.context[1]
        migration.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")

        migrator.apply(1, 1, 1)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)
      end
    end
  end

  describe "#rollback(id)" do
    context "with migration applied" do
      it "removes migration from the list of applied" do
        db, migrator = prepared_migrator
        fake_migration db

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
        migrator.rollback(1)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
      end

      it "executes migration down statements" do
        db, migrator = prepared_migrator
        fake_migration db
        create_dummy db

        migration = migrator.context[1]
        migration.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        migrator.rollback(1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)
      end

      it "removes only applied migrations" do
        db, migrator = prepared_migrator
        fake_migration db
        create_dummy db

        migration = migrator.context[2]
        migration.add(:rollback, "INSERT INTO dummy (value) VALUES (20);")

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
        migrator.rollback(2)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
      end

      it "applies rollback within a transaction to avoid partial execution" do
        db, migrator = prepared_migrator
        fake_migration db
        create_dummy db

        migration = migrator.context[1]
        migration.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")
        migration.add(:rollback, "INSERT INTO foo (value)")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        expect_raises(Exception) do
          migrator.rollback(1)
        end
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)
      end
    end
  end

  describe "#rollback(ids)" do
    context "with no migrations applied" do
      it "does not rollback non-applied migration" do
        db, migrator = prepared_migrator
        create_dummy db

        m1 = migrator.context[1]
        m1.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")
        m3 = migrator.context[3]
        m3.add(:rollback, "INSERT INTO dummy (value) VALUES (30);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        migrator.rollback(3, 1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
      end
    end

    context "with migrations applied" do
      it "removes migration from the list of applied" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 2

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
        migrator.rollback(2, 1)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
      end

      it "considers migration only once" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        create_dummy db

        migration = migrator.context[1]
        migration.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        migrator.rollback(1, 1, 1, 1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(1)
      end

      it "executes migration down statements" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 2
        create_dummy db

        m1 = migrator.context[1]
        m1.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")
        m2 = migrator.context[2]
        m2.add(:rollback, "INSERT INTO dummy (value) VALUES (20);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        migrator.rollback(2, 1)
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(2)
        db.scalar("SELECT MAX(value) FROM dummy;").as(Int64).should eq(20)
      end

      it "applies rollback within a transaction to avoid partial execution" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 2
        create_dummy db

        m1 = migrator.context[1]
        m1.add(:rollback, "INSERT INTO foo (value)")
        m2 = migrator.context[2]
        m2.add(:rollback, "INSERT INTO dummy (value) VALUES (10);")

        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        expect_raises(Exception) do
          migrator.rollback(2, 1)
        end
        db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(2)
      end
    end
  end

  describe "#rollback_plan" do
    context "with no migration applied" do
      it "returns an empty list of migrations" do
        _, migrator = prepared_migrator

        ids = migrator.rollback_plan
        ids.should be_empty
      end
    end

    context "dealing with batches" do
      it "returns the list of migrations in reverse order" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 2

        ids = migrator.rollback_plan
        ids.should_not be_empty
        ids.should eq([2, 1])
      end

      it "returns only the list of migrations in the last batch" do
        db, migrator = prepared_migrator
        fake_migration db, 1, 1
        fake_migration db, 2, 1
        fake_migration db, 4, 2

        ids = migrator.rollback_plan
        ids.should_not be_empty
        ids.should eq([4])
      end
    end

    context "migrations not available locally" do
      it "excludes migrations not locally available" do
        db, migrator = prepared_migrator
        fake_migration db, 5

        ids = migrator.rollback_plan
        ids.should be_empty
      end
    end
  end

  describe "#reset_plan" do
    context "with no migration applied" do
      it "returns an empty list of migrations" do
        _, migrator = prepared_migrator

        ids = migrator.reset_plan
        ids.should be_empty
      end
    end

    context "with a single batch" do
      it "returns a list of migrations in reverse order" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 3

        ids = migrator.reset_plan
        ids.should_not be_empty
        ids.should eq([3, 1])
      end

      it "excludes migraitons not locally available" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 5

        ids = migrator.reset_plan
        ids.should_not be_empty
        ids.should eq([1])
      end
    end

    context "with multiple batches" do
      it "returns list of migrations in reverse order" do
        db, migrator = prepared_migrator
        fake_migration db, 1, 1
        fake_migration db, 3, 1
        fake_migration db, 2, 2
        fake_migration db, 4, 2

        ids = migrator.reset_plan
        ids.should_not be_empty
        ids.should eq([4, 2, 3, 1])
      end
    end
  end

  describe "#pending?" do
    it "returns true when no migration was applied" do
      _, migrator = prepared_migrator

      migrator.pending?.should be_true
    end

    it "returns false when all migrations were applied" do
      db, migrator = prepared_migrator
      fake_migration db, 1
      fake_migration db, 2
      fake_migration db, 3
      fake_migration db, 4

      migrator.pending?.should be_false
    end
  end

  describe "#apply!" do
    context "with completely empty database" do
      it "prepares the migration table and applies migrations" do
        db = memory_db
        migrator = ready_migrator(db)

        migrator.apply!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)
      end
    end

    context "with no existing migration applied" do
      it "applies all available migrations as single batch" do
        db, migrator = prepared_migrator

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        migrator.apply!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
      end
    end

    context "with existing batches" do
      it "applies pending migrations as new batch" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 3

        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(1)
        migrator.apply!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(4)
        db.scalar("SELECT MAX(batch) FROM drift_migrations;").as(Int64).should eq(2)
      end
    end
  end

  describe "#reset!" do
    context "with no migration applied" do
      it "does nothing" do
        db, migrator = prepared_migrator

        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
        migrator.reset!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
      end
    end

    context "with some applied migrations" do
      it "resets the migration status" do
        db, migrator = prepared_migrator
        fake_migration db, 1
        fake_migration db, 3

        migrator.reset!
        db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
      end
    end
  end

  describe "(apply callback cycle)" do
    it "triggers before a migration is applied" do
      _, migrator = prepared_migrator

      count = 0
      migrator.before_apply do |_|
        count += 1
      end

      migrator.apply(1)
      count.should eq(1)
    end

    it "triggers after a migration has been applied" do
      _, migrator = prepared_migrator

      count = 0
      migrator.after_apply do |_, _|
        count += 1
      end

      migrator.apply(1)
      count.should eq(1)
    end

    it "triggers callbacks in sequence" do
      _, migrator = prepared_migrator

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
      db, migrator = prepared_migrator
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
    end
  end

  describe "(rollback callback cycle)" do
    it "triggers before a migration is rolled back" do
      db, migrator = prepared_migrator
      fake_migration db, 1

      count = 0
      migrator.before_rollback do |_|
        count += 1
      end

      migrator.rollback(1)
      count.should eq(1)
    end

    it "triggers after a migration has been rolled back" do
      db, migrator = prepared_migrator
      fake_migration db, 1

      count = 0
      migrator.after_rollback do |_, _|
        count += 1
      end

      migrator.rollback(1)
      count.should eq(1)
    end

    it "triggers callbacks in sequence" do
      db, migrator = prepared_migrator
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
    end

    it "does not trigger if migration is not applied" do
      _, migrator = prepared_migrator

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
      db, migrator = prepared_migrator
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
    end
  end

  describe "#applied" do
    it "returns an empty list when no migrations were applied" do
      _, migrator = prepared_migrator

      migrator.applied.should be_empty
    end

    it "returns ordered list of applied migrations" do
      db, migrator = prepared_migrator
      fake_migration db, 1
      fake_migration db, 2

      entries = migrator.applied
      entries.should_not be_empty
      entries.size.should eq(2)

      mig1 = entries.first
      mig1.id.should eq(1)
    end

    it "returns only known applied migrations" do
      db, migrator = prepared_migrator
      fake_migration db, 2
      fake_migration db, 5

      entries = migrator.applied
      entries.size.should eq(1)

      mig2 = entries.first
      mig2.id.should eq(2)
    end
  end
end
