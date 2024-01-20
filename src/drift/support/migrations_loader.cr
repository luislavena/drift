# Copyright 2024 Luis Lavena
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
  module Support
    # :nodoc:
    ID_PATTERN = /(^[0-9]+)/

    class MigrationsLoader
      def initialize(@io : IO, @path : String)
      end

      def run
        migration_files = Dir.glob(File.join(@path, "*.sql")).sort!

        migration_files.each do |path|
          filename = File.basename(path)

          # ctx.add Drift::Migration.from_io(SQL, id, filename)\n

          @io << "# #{filename}\n"
          @io << "ctx.add Drift::Migration.from_io("
          File.read(path).inspect(@io)
          @io << ", "
          @io << ID_PATTERN.match(filename).try &.[1]
          @io << ", "
          filename.inspect(@io)
          @io << ")\n\n"
        end
      end
    end
  end
end

path = File.expand_path(ARGV[0], ARGV[1])

Drift::Support::MigrationsLoader.new(STDOUT, path).run
