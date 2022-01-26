require "../spec_helper"
require "sqlite3"

def db_connection
  DB.connect "sqlite3:%3Amemory%3A"
end

describe Drift::Conductor do
  context "(folder with migrations)" do
    pending "loads all migrations by order" do
      conductor = Drift::Conductor.new
      conductor.load_migrations fixture_path("sequence")

      conductor.migrations.size.should eq(2)
    end
  end
end
