require "db"
require "./tracker/*"

module Drift
  abstract class Tracker
    def self.for(db : DB::Database)
      case db.uri.scheme
      when "sqlite3"
        SQLite3.new(db)
      end
    end

    def self.for(connection : DB::Connection)
      case connection.context.uri.scheme
      when "sqlite3"
        SQLite3.new(connection)
      end
    end
  end
end
