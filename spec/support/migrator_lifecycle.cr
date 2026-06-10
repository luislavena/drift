# Copyright 2026 Luis Lavena
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

alias LifecycleDB = DB::Database | DB::Connection

# Migrations used by the cross-engine lifecycle specs. The SQL here must be
# valid on SQLite, MySQL and PostgreSQL alike.
def lifecycle_context
  ctx = Drift::Context.new

  m1 = Drift::Migration.new(1)
  m1.add(:up, "CREATE TABLE drift_test_people (id BIGINT NOT NULL, name VARCHAR(50) NOT NULL);")
  m1.add(:down, "DROP TABLE drift_test_people;")
  ctx.add m1

  m2 = Drift::Migration.new(2)
  m2.add(:up, "INSERT INTO drift_test_people (id, name) VALUES (1, 'first');")
  m2.add(:down, "DELETE FROM drift_test_people;")
  ctx.add m2

  ctx
end

# Yields a database handle with no leftover Drift state. Tables are dropped
# before (not after) each example, so an interrupted run never poisons the
# next one. In-memory SQLite starts empty, but dropping is harmless there.
def with_clean_db(factory : -> LifecycleDB, &)
  db = factory.call
  begin
    db.exec "DROP TABLE IF EXISTS drift_migrations;"
    db.exec "DROP TABLE IF EXISTS drift_test_people;"
    yield db
  ensure
    db.close
  end
end

# Registers the Migrator behavioral contract against one engine. Every
# engine must pass exactly the same examples; only the factory differs.
def it_behaves_like_a_migrator(engine : String, factory : -> LifecycleDB)
  describe "Drift::Migrator (#{engine})" do
    it "prepares the migrations table" do
      with_clean_db(factory) do |db|
        migrator = Drift::Migrator.new(db, lifecycle_context)

        migrator.prepared?.should be_false
        migrator.prepare!
        migrator.prepared?.should be_true

        # prepare! is idempotent
        migrator.prepare!
        migrator.prepared?.should be_true
      end
    end

    it "applies pending migrations and records them" do
      with_clean_db(factory) do |db|
        migrator = Drift::Migrator.new(db, lifecycle_context)

        migrator.apply!

        migrator.pending?.should be_false
        migrator.applied_ids.should eq([1, 2])
        migrator.applied?(1).should be_true

        entries = migrator.applied
        entries.size.should eq(2)

        entry = entries.first
        entry.id.should eq(1)
        entry.batch.should eq(1)
        entry.applied_at.should be_close(Time.utc, 5.seconds)
        entry.duration_ns.should be >= 0

        db.scalar("SELECT COUNT(*) FROM drift_test_people;").should eq(1)
      end
    end

    it "does nothing when migrations are applied again" do
      with_clean_db(factory) do |db|
        migrator = Drift::Migrator.new(db, lifecycle_context)

        migrator.apply!
        migrator.apply!

        migrator.applied_ids.should eq([1, 2])
        db.scalar("SELECT COUNT(*) FROM drift_test_people;").should eq(1)
      end
    end

    it "rolls back only the last batch" do
      with_clean_db(factory) do |db|
        migrator = Drift::Migrator.new(db, lifecycle_context)

        migrator.prepare!
        migrator.apply(1)
        migrator.apply(2) # second batch

        migrator.rollback_plan.should eq([2])
        migrator.rollback(migrator.rollback_plan)

        migrator.applied_ids.should eq([1])
        db.scalar("SELECT COUNT(*) FROM drift_test_people;").should eq(0)
      end
    end

    it "resets all applied migrations in reverse order" do
      with_clean_db(factory) do |db|
        migrator = Drift::Migrator.new(db, lifecycle_context)

        migrator.apply!

        rolled_back = Array(Int64).new
        migrator.before_rollback do |id|
          rolled_back.push id
        end

        migrator.reset!

        rolled_back.should eq([2, 1])
        migrator.applied_ids.should be_empty
        migrator.pending?.should be_true
      end
    end
  end
end
