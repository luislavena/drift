# Copyright 2022 Luis Lavena
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Drift
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
    getter filename : String? = nil

    @statements : Hash(Direction, Array(String))

    def initialize(@id : Int64, @filename : String? = nil)
      @statements = Direction.values.to_h { |direction|
        {direction, Array(String).new}
      }
    end

    def add(direction : Direction, statement : String)
      @statements[direction].push statement
    end

    def statements_for(direction : Direction)
      @statements[direction]
    end

    def self.from_io(io, id : Int64, filename : String? = nil) : self
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

    def self.load_file(filename : String) : self
      basename = File.basename(filename)

      # extract ID from filename
      id = (ID_PATTERN.match(basename).try &.[1]).try &.to_i64

      if id
        File.open(filename) do |io|
          from_io(io, id, basename)
        end
      else
        raise MigrationError.new("Cannot determine migration ID from file '#{filename}'")
      end
    end
  end
end
