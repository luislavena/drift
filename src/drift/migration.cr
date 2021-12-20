module Drift
  class MigrationError < Exception
  end

  class Migration
    getter id : Int64

    # :nodoc:
    ID_PATTERN = /(^[0-9]+)/

    def initialize(@id)
    end

    def self.from_io(io : IO | String, path : String)
      # extract ID from filename
      filename = File.basename(path)
      id = (ID_PATTERN.match(filename).try &.[1]).try &.to_i64

      if id
        migration = new(id)
      else
        raise MigrationError.new("Unable to determine migration ID from path '#{path}'")
      end
    end
  end
end
