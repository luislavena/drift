require "../spec_helper"

describe Drift::Migration do
  describe ".from_io" do
    it "extracts ID from given filename" do
      migration = Drift::Migration.from_io("", "01_migration.sql")
      migration.id.should eq(1)
    end

    it "accepts long migration IDs" do
      migration = Drift::Migration.from_io("", "20211225105157_empty_long_id.sql")
      migration.id.should eq(20211225105157_i64)
    end

    it "accepts filename in nested directories" do
      migration = Drift::Migration.from_io("", "/app/date/20211231/migrations/002_create_users.sql")
      migration.id.should eq(2)
    end

    it "raises error when filename do not contain an ID" do
      expect_raises(Drift::MigrationError, /Unable to determine migration ID/) do
        Drift::Migration.from_io("", "no_migration_id.sql")
      end
    end
  end
end
