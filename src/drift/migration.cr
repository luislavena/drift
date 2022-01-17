module Drift
  class MigrationError < Exception
  end

  class Migration
    enum Direction
      Up
      Down
    end

    # :nodoc:
    ID_PATTERN = /(^[0-9]+)/

    getter id : Int64

    @statements : Hash(Direction, Array(String))

    def initialize(@id)
      @statements = Direction.values.to_h { |direction| {direction, [] of String} }
    end

    def statements_for(direction : Direction)
      @statements[direction]
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

      # TODO: parse statements from IO

      migration
    end
  end
end
