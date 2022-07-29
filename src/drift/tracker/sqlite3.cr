require "../tracker"

module Drift
  abstract class Tracker
    class SQLite3 < Tracker
      private getter db : DB::Database | DB::Connection

      def initialize(@db)
      end
    end
  end
end
