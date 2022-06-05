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
      migration.add(:up, "SELECT 1 AS one;")
      migration.add(:up, "SELECT 2 AS two;")
      migration.add(:down, "SELECT 3 AS three;")

      migration.statements_for(:up).size.should eq(2)
      migration.statements_for(:up).first.should eq("SELECT 1 AS one;")

      migration.statements_for(:down).size.should eq(1)
      migration.statements_for(:down).first.should eq("SELECT 3 AS three;")
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
      it "parses statement on a given direction" do
        data = <<-SQL
          -- drift:up
          SELECT 1;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        migration.statements_for(:up).size.should eq(1)
        migration.statements_for(:up).first.should eq("SELECT 1;")
      end

      it "ignores statements without indicated direction" do
        contents = <<-SQL
          SELECT 4;
          SQL

        migration = Drift::Migration.from_io(contents, 1)
        migration.statements_for(:up).should be_empty
        migration.statements_for(:down).should be_empty
      end

      it "recognizes multiple statements in multiple directions" do
        data = <<-SQL
          -- drift:up
          SELECT 1;
          SELECT 2;

          -- drift:down
          SELECT 3;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        up_statements = migration.statements_for(:up)
        up_statements.size.should eq(2)

        down_statements = migration.statements_for(:down)
        down_statements.size.should eq(1)
        down_statements.first.should eq("SELECT 3;")
      end

      it "recognizes multi line statements" do
        create_statement = <<-SQL
          CREATE TABLE IF NOT EXISTS humans (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
          );
          SQL

        data = <<-SQL
          -- drift:up
          #{create_statement}
          CREATE INDEX IF NOT EXISTS idx_humans_name ON humans(name);

          -- drift:down
          DROP TABLE IF EXISTS humans;
          SQL

        migration = Drift::Migration.from_io(data, 1)
        migration.statements_for(:up).size.should eq(2)
        migration.statements_for(:down).size.should eq(1)

        create_statement = migration.statements_for(:up).first
        create_statement.should eq(create_statement)
      end
    end
  end

  describe ".load_file" do
    it "populates migration with file contents" do
      file_path = fixture_path("sequence", "20211219152312_create_humans.sql")
      migration = Drift::Migration.load_file(file_path)

      migration.id.should eq(20211219152312)
      migration.filename.should eq("20211219152312_create_humans.sql")
      migration.statements_for(:up).size.should eq(2)
      migration.statements_for(:down).size.should eq(2)
    end

    it "raises error when unable to determine migration ID" do
      expect_raises(Drift::MigrationError, /Cannot determine migration ID from file/) do
        Drift::Migration.load_file("no_id_migration.sql")
      end
    end
  end
end
