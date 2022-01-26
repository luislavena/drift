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

    # :nodoc:
    MAGIC_MARKER = "-- drift:"

    getter id : Int64
    getter filename : String

    @statements : Hash(Direction, Array(String))

    def initialize(@id, @filename = "")
      @statements = Direction.values.to_h { |direction| {direction, [] of String} }
    end

    def add(direction : Direction, statement : String)
      @statements[direction] << statement
    end

    def statements_for(direction : Direction)
      @statements[direction]
    end

    def self.from_filename?(filename : String | Path)
      # extract ID from filename
      id = (ID_PATTERN.match(File.basename(filename)).try &.[1]).try &.to_i64
      return unless id
      return unless File.exists?(filename)

      File.open(filename) do |io|
        from_io(io, id, File.basename(filename))
      end
    end

    def self.from_filename(filename : String | Path)
      from_filename?(filename) || raise MigrationError.new("Unable to load migration from '#{filename}'")
    end

    def self.from_io(io, id : Int64, filename : String = "")
      migration = new(id, filename)

      buffer = IO::Memory.new
      direction = nil

      io.each_line do |line|
        stripped_line = line.strip

        # detect markers
        if stripped_line.starts_with?(MAGIC_MARKER)
          case stripped_line[MAGIC_MARKER.size..-1]
          when "up"
            direction = Direction::Up
            next
          when "down"
            direction = Direction::Down
            next
          else
            # TBD: support other commands?
          end
        end

        next unless direction

        # write raw line into buffer
        buffer.puts line

        if stripped_line.ends_with?(';')
          # strip new line when saveing the new statement
          migration.add(direction, buffer.to_s.strip)
          buffer.clear
        end
      end

      migration
    end
  end
end
