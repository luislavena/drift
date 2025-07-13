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

private def memory_db
  DB.connect("sqlite3:%3Amemory%3A")
end

describe Drift::Migration do
  describe ".new" do
    it "accepts an optional filename" do
      migration = Drift::Migration.new(1, "0001_create_users.sql")
      migration.filename.should eq("0001_create_users.sql")

      migration = Drift::Migration.new(2)
      migration.filename.should be_nil
    end

    it "accepts multiple statements on each direction" do
      migration = Drift::Migration.new(1)
      migration.add(:migrate, "SELECT 1 AS one;")
      migration.add(:migrate, "SELECT 2 AS two;")
      migration.add(:rollback, "SELECT 3 AS three;")

      migration.statements_for(:migrate).size.should eq(2)
      migration.statements_for(:migrate).first.should eq("SELECT 1 AS one;")

      migration.statements_for(:rollback).size.should eq(1)
      migration.statements_for(:rollback).first.should eq("SELECT 3 AS three;")
    end
  end

  describe ".from_io" do
    it "accepts an optional filename" do
      migration = Drift::Migration.from_io("", 1)
      migration.id.should eq(1)
      migration.filename.should be_nil

      migration = Drift::Migration.from_io("", 2, "0001_create_users.sql")
      migration.id.should eq(2)
      migration.filename.should eq("0001_create_users.sql")
    end

    context "(magic comments)" do
      it "parses statement on a given type" do
        data = <<-SQL
          -- drift:migrate
          SELECT 1;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        migration.statements_for(:migrate).size.should eq(1)
        migration.statements_for(:migrate).first.should eq("SELECT 1;")
      end

      it "ignores statements without indicated type" do
        contents = <<-SQL
          SELECT 4;
          SQL

        migration = Drift::Migration.from_io(contents, 1)
        migration.statements_for(:migrate).should be_empty
        migration.statements_for(:rollback).should be_empty
      end

      it "recognizes multiple statements of any type" do
        data = <<-SQL
          -- drift:migrate
          SELECT 1;
          SELECT 2;

          -- drift:rollback
          SELECT 3;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        migrate_statements = migration.statements_for(:migrate)
        migrate_statements.size.should eq(2)

        rollback_statements = migration.statements_for(:rollback)
        rollback_statements.size.should eq(1)
        rollback_statements.first.should eq("SELECT 3;")
      end

      it "recognizes multi line statements" do
        create_statement = <<-SQL
          CREATE TABLE IF NOT EXISTS humans (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
          );
          SQL

        data = <<-SQL
          -- drift:migrate
          #{create_statement}
          CREATE INDEX IF NOT EXISTS idx_humans_name ON humans(name);

          -- drift:rollback
          DROP TABLE IF EXISTS humans;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        migration.statements_for(:migrate).size.should eq(2)
        migration.statements_for(:rollback).size.should eq(1)

        create_statement = migration.statements_for(:migrate).first
        create_statement.should eq(create_statement)
      end

      it "handles mixing regular statements with multi-statement blocks" do
        mixed_statement = <<-SQL
          -- drift:migrate
          CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            created_at TIMESTAMP,
            updated_at TIMESTAMP
          );

          -- drift:begin
          CREATE TRIGGER set_timestamp_on_insert
          BEFORE INSERT ON users
          FOR EACH ROW
          BEGIN
            NEW.created_at = CURRENT_TIMESTAMP;
            NEW.updated_at = CURRENT_TIMESTAMP;
          END;
          -- drift:end

          CREATE INDEX idx_users_name ON users(name);

          -- drift:rollback
          DROP INDEX IF EXISTS idx_users_name;
          DROP TRIGGER IF EXISTS set_timestamp_on_insert;
          DROP TABLE IF EXISTS users;
          SQL

        migration = Drift::Migration.from_io(mixed_statement, 1)

        # Should have 3 migrate statements: table creation, trigger, and index
        migration.statements_for(:migrate).size.should eq(3)

        # Should have 3 rollback statements: index drop, trigger drop, and table drop
        migration.statements_for(:rollback).size.should eq(3)
      end
    end
  end

  describe ".load_file" do
    it "populates migration with file contents" do
      file_path = fixture_path("sequence", "20211219152312_create_humans.sql")
      migration = Drift::Migration.load_file(file_path)

      migration.id.should eq(20211219152312)
      migration.filename.should eq("20211219152312_create_humans.sql")
      migration.statements_for(:migrate).size.should eq(2)
      migration.statements_for(:rollback).size.should eq(2)
    end

    it "loads multi-statement migration with begin/end markers correctly" do
      file_path = fixture_path("trigger", "20250302234927_create_timestamp_trigger.sql")
      migration = Drift::Migration.load_file(file_path)

      migration.statements_for(:migrate).size.should eq(1)
      migrate_stmt = migration.statements_for(:migrate).first
      migrate_stmt.should contain("CREATE TRIGGER update_timestamp")
      migrate_stmt.should contain("UPDATE employees")
      migrate_stmt.should contain("INSERT INTO")

      migration.statements_for(:rollback).size.should eq(1)
      migration.statements_for(:rollback).first.should eq("DROP TRIGGER IF EXISTS update_timestamp;")
    end

    it "raises error when unable to determine migration ID" do
      expect_raises(Drift::MigrationError, /Cannot determine migration ID from file/) do
        Drift::Migration.load_file("no_id_migration.sql")
      end
    end
  end

  describe "#run(DB)" do
    it "executes statements for a direction in the given order" do
      db = memory_db
      db.exec("CREATE TABLE IF NOT EXISTS dummy (id INTEGER PRIMARY KEY NOT NULL, value INTEGER NOT NULL);")
      db.scalar("SELECT COUNT(id) FROM dummy;").as(Int64).should eq(0)

      migration = Drift::Migration.new(1)
      migration.add(:migrate, "INSERT INTO dummy (value) VALUES (20);")
      migration.add(:migrate, "INSERT INTO dummy (value) VALUES (10);")

      migration.run(:migrate, db)

      values = db.query_all "SELECT value FROM dummy ORDER BY id ASC;", &.read(Int64)
      values.size.should eq(2)
      values.should eq([20, 10])
    end
  end
end
