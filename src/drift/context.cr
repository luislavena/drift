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

require "./migration"

module Drift
  class Context
    # :nodoc:
    LOADED = "(loaded)"

    @available_migrations = Hash(Int64, String).new
    @migrations = Hash(Int64, Migration).new

    def add(migration : Drift::Migration)
      @available_migrations[migration.id] = LOADED
      @migrations[migration.id] = migration
    end

    def empty?
      @available_migrations.empty?
    end

    def ids
      @available_migrations.keys.sort!
    end

    def load_path(path : String)
      # build a list of .sql files to load
      migration_files = Dir.glob(File.join(path, "*.sql")).sort!

      # extract the IDs of found filenames for mapping
      migration_files.each do |filename|
        next unless id = Drift.extract_id?(filename)

        @available_migrations[id] = filename
      end
    end

    def [](id : Int64)
      self[id]? || raise ContextError.new("Missing migration '#{id}'")
    end

    def []?(id : Int64)
      if found = @migrations[id]?
        return found
      end

      if path = @available_migrations[id]?
        migration = Drift::Migration.load_file(path)
        @migrations[migration.id] = migration
      end
    end
  end
end
