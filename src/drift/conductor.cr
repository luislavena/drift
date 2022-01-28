require "db"
require "./migration"

module Drift
  class Conductor
    getter migrations : Hash(Int64, Drift::Migration)

    def initialize
      @migrations = Hash(Int64, Drift::Migration).new
    end

    def load_migrations!(path : String | Path)
      # clear existing list of migrations
      @migrations.clear

      entries = Dir.glob(File.join(path, "*.sql")).sort!

      entries.each do |entry|
        migration = Migration.from_filename(entry)

        @migrations[migration.id] = migration
      end
    end
  end
end
