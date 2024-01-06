# Copyright 2023 Luis Lavena
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

require "./command"

module Drift
  module Commands
    class New < Command
      MIGRATION_TEMPLATE = <<-SQL
      -- drift:migrate

      -- drift:rollback
      SQL

      def run(*args)
        migration_name = args.first?
        raise Drift::Error.new("A migration name is required.") unless migration_name

        timestamp = Time.local.to_s("%Y%m%d%H%M%S")
        filename = "#{timestamp}_#{migration_name.underscore}.sql"

        full_migration = File.join(options.migrations_path, filename)
        raise Drift::Error.new("migration file '#{full_migration}' already exists.") if File.exists?(full_migration)

        # ensure directory exists before creating file
        Dir.mkdir_p(options.migrations_path)

        File.write(full_migration, MIGRATION_TEMPLATE)
        puts "INFO: Created #{full_migration}"
      end
    end
  end
end
