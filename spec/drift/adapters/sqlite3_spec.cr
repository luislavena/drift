# Copyright 2023 Luis Lavena
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

require "../../spec_helper"

require "sqlite3"

private def memory_db
  DB.connect("sqlite3:%3Amemory%3A")
end

private def build_adapter(db)
  Drift::Adapters::SQLite3.new(db)
end

private def prepared_adapter
  db = memory_db
  adapter = build_adapter(db).tap { |a| a.create_schema }

  {db, adapter}
end

private struct MigrationEntry
  include DB::Serializable

  getter id : Int64
  getter batch : Int64
  getter applied_at : Time
  getter duration_ns : Int64
end

describe Drift::Adapters::SQLite3 do
  describe "#schema_exists?" do
    it "returns false when no migrations table exists" do
      adapter = build_adapter(memory_db)
      adapter.schema_exists?.should be_false
    end

    it "returns true when migrations table exists" do
      db = memory_db
      db.exec "CREATE TABLE drift_migrations (id INTEGER PRIMARY KEY, dummy TEXT);"

      adapter = build_adapter(db)
      adapter.schema_exists?.should be_true
    end
  end

  describe "#create_schema" do
    it "creates migration table if missing" do
      db = memory_db
      adapter = build_adapter(db)
      adapter.create_schema

      db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
    end
  end

  describe "#track_migration" do
    it "records individual migration information into migrations table" do
      db, adapter = prepared_adapter

      # id, batch, duration
      adapter.track_migration 1, 1, 3.seconds

      # id, batch, applied_at, duration_ns
      result = db.query_one("SELECT id, batch, applied_at, duration_ns FROM drift_migrations WHERE id = ? LIMIT 1;", 1, as: MigrationEntry)
      db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(1)

      result.id.should eq(1)
      result.batch.should eq(1)
      result.applied_at.should be_close(Time.utc, 1.second)
      result.duration_ns.should eq(3.seconds.total_nanoseconds)
    end
  end

  describe "#untrack_migration" do
    it "removes migration information from migrations table" do
      db, adapter = prepared_adapter
      db.exec "INSERT INTO drift_migrations (id, batch, applied_at, duration_ns) VALUES (?, ?, ?, ?);", 1, 1, Time.utc, 100000

      adapter.untrack_migration 1
      db.scalar("SELECT COUNT(id) FROM drift_migrations;").as(Int64).should eq(0)
    end
  end
end
