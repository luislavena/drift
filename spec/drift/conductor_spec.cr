require "../spec_helper"
require "sqlite3"

private def db_connection
  DB.connect "sqlite3:%3Amemory%3A"
end

describe Drift::Conductor do
  context "(folder with migrations)" do
    it "loads all migrations in sequence" do
      conductor = Drift::Conductor.new

      conductor.migrations.size.should eq(0)
      conductor.load_migrations! fixture_path("sequence")

      conductor.migrations.size.should eq(2)
      conductor.migrations.keys.should eq([
        20211219152312_i64,
        20211220182717_i64,
      ])
    end
  end
end
