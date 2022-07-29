require "../spec_helper"
require "sqlite3"

private def sqlite3_memory_db
  DB.open "sqlite3:%3Amemory%3A"
end

private def sqlite3_memory_connection
  DB.connect "sqlite3:%3Amemory%3A"
end

describe Drift::Tracker do
  describe ".for" do
    context "(SQLite3)" do
      it "correctly maps a database to SQLite3" do
        db = sqlite3_memory_db
        tracker = Drift::Tracker.for(db)

        tracker.should be_a(Drift::Tracker::SQLite3)
      end

      it "correctly maps a connection to SQLite3" do
        connection = sqlite3_memory_connection
        tracker = Drift::Tracker.for(connection)

        tracker.should be_a(Drift::Tracker::SQLite3)
      end
    end
  end
end
