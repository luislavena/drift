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
    # :nodoc:
    enum Type
      Up
      Down
    end

    # :nodoc:
    MAGIC_MARKER = "-- drift:"

    getter id : Int64
    getter filename : String? = nil

    @statements : Hash(Type, Array(String))

    def initialize(@id : Int64, @filename : String? = nil)
      @statements = Type.values.to_h { |type|
        {type, Array(String).new}
      }
    end

    def add(type : Type, statement : String)
      @statements[type].push statement
    end

    def run(type : Type, db)
      statements_for(type).each do |statement|
        db.exec statement
      end
    end

    def statements_for(type : Type)
      @statements[type]
    end

    def self.from_io(io, id : Int64, filename : String? = nil) : self
      migration = new(id, filename)

      buffer = IO::Memory.new
      type = nil
      multi_statement_mode = false
      deprecated_warning_shown = false

      io.each_line do |line|
        stripped_line = line.strip
        # detect markers
        if stripped_line.starts_with?(MAGIC_MARKER)
          case stripped_line[MAGIC_MARKER.size..-1]
          when "up"
            type = Type::Up
            next
          when "down"
            type = Type::Down
            next
          when "migrate"
            unless deprecated_warning_shown
              STDERR.puts "DEPRECATED: 'drift:migrate' marker in '#{filename || id}' is deprecated, use 'drift:up' instead"
              deprecated_warning_shown = true
            end
            type = Type::Up
            next
          when "rollback"
            unless deprecated_warning_shown
              STDERR.puts "DEPRECATED: 'drift:rollback' marker in '#{filename || id}' is deprecated, use 'drift:down' instead"
              deprecated_warning_shown = true
            end
            type = Type::Down
            next
          when "begin"
            multi_statement_mode = true
            next
          when "end"
            if multi_statement_mode && !buffer.empty? && type
              # Save the multi-line statement when end marker is reached
              migration.add(type, buffer.to_s.strip)
              buffer.clear
            end
            multi_statement_mode = false
            next
          else
            # TBD: support other commands?
          end
        end

        next unless type

        # write raw line into buffer
        buffer.puts line

        # In multi-statement mode, don't process semicolons as statement separators
        if !multi_statement_mode && stripped_line.ends_with?(';')
          # strip new line when saving the new statement
          migration.add(type, buffer.to_s.strip)
          buffer.clear
        end
      end

      migration
    end

    def self.load_file(filename : String) : self
      basename = File.basename(filename)

      if id = Drift.extract_id?(basename)
        File.open(filename) do |io|
          from_io(io, id, basename)
        end
      else
        raise MigrationError.new("Cannot determine migration ID from file '#{filename}'")
      end
    end
  end
end
