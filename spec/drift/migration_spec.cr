require "../spec_helper"

describe Drift::Migration do
  context "(new)" do
    it "accepts multiple statements on each direction" do
      migration = Drift::Migration.new(1_i64)
      migration.add(:up, "SELECT 1 AS one;")
      migration.add(:up, "SELECT 2 AS two;")
      migration.add(:down, "SELECT 3 AS three;")

      migration.statements_for(:up).size.should eq(2)
      migration.statements_for(:up).first.should eq("SELECT 1 AS one;")

      migration.statements_for(:down).size.should eq(1)
      migration.statements_for(:down).first.should eq("SELECT 3 AS three;")
    end

    it "keeps an optional filename" do
      migration = Drift::Migration.new(1_i64, "0001_create_users.sql")
      migration.filename.should eq("0001_create_users.sql")
    end
  end

  describe ".from_io" do
    context "(magic comments)" do
      it "recognizes up direction given to statement" do
        contents = <<-SQL
          -- drift:up
          SELECT 1;
          SQL

        migration = Drift::Migration.from_io(contents, 1_i64)
        up_statements = migration.statements_for(:up)
        up_statements.size.should eq(1)
        up_statements.first.should eq("SELECT 1;")
      end

      it "recognizes multiple statements on the same direction" do
        contents = <<-SQL
          -- drift:up
          SELECT 1;
          SELECT 2;
          SQL

        migration = Drift::Migration.from_io(contents, 1_i64)
        up_statements = migration.statements_for(:up)
        up_statements.size.should eq(2)
        up_statements.last.should eq("SELECT 2;")
      end

      it "ignores statements without prior direction" do
        contents = <<-SQL
          SELECT 4;
          SQL

        migration = Drift::Migration.from_io(contents, 1_i64)
        migration.statements_for(:up).should be_empty
        migration.statements_for(:down).should be_empty
      end

      it "recognizes statements in multiple directions" do
        contents = <<-SQL
          -- drift:up
          SELECT 1;

          -- drift:down
          SELECT 3;
          SQL

        migration = Drift::Migration.from_io(contents, 1_i64)
        up_statements = migration.statements_for(:up)
        up_statements.size.should eq(1)

        down_statements = migration.statements_for(:down)
        down_statements.size.should eq(1)
        down_statements.first.should eq("SELECT 3;")
      end

      it "recognizes multi line statements" do
        create_statement = <<-SQL
          CREATE TABLE IF NOT EXISTS humans
          (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
          );
          SQL

        contents = <<-SQL
          -- drift:up
          #{create_statement}

          CREATE INDEX IF NOT EXISTS idx_humans_name ON humans(name);

          -- drift:down
          DROP TABLE IF EXISTS humans;
          SQL

        migration = Drift::Migration.from_io(contents, 1_i64)
        migration.statements_for(:up).size.should eq(2)
        migration.statements_for(:down).size.should eq(1)

        create_statement = migration.statements_for(:up).first
        create_statement.should eq(create_statement)
      end
    end

    it "optionally sets the given filename" do
      migration = Drift::Migration.from_io("", 1_i64)
      migration.filename.should be_nil

      migration = Drift::Migration.from_io("", 1_i64, "0001_create_users.sql")
      migration.filename.should eq("0001_create_users.sql")
    end
  end

  describe ".from_filename" do
    it "populates the migration with file contents and ID" do
      path = fixture_path("sequence", "20211219152312_create_humans.sql")
      migration = Drift::Migration.from_filename(path)

      migration.id.should eq(20211219152312_i64)
      migration.filename.should eq("20211219152312_create_humans.sql")
      migration.statements_for(:up).size.should eq(2)
      migration.statements_for(:down).size.should eq(1)
    end

    it "raises error when ID cannot be extracted from filename" do
      expect_raises(Drift::MigrationError, /Cannot determine migration ID from file/) do
        Drift::Migration.from_filename("no_id_migration.sql")
      end
    end
  end
end
