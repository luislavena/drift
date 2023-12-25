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

require "compiler/crystal/tools/table_print"

require "./command"

module Drift
  module Commands
    class Status < Command
      def run
        with_migrator do |migrator|
          check_prepared! migrator

          applied = migrator.applied

          # skip empty table when no migration is found
          migration_ids = migrator.context.ids
          return if migration_ids.empty?

          Crystal::TablePrint.new(STDOUT).build do
            # header
            separator
            row do
              cell "Migration"
              cell "Ran?"
              cell "Batch"
              cell "Applied at"
              cell "Duration", align: :right
            end
            separator

            migration_ids.each do |id|
              row do
                if filename = migrator.context[id].filename
                  cell filename
                else
                  cell id.to_s
                end

                if migration = applied.find { |m| m.id == id }
                  cell "Yes"
                  cell migration.batch.to_s, align: :right
                  cell migration.applied_at.to_s
                  cell human_span(migration.duration), align: :right
                else
                  4.times { cell "" }
                end
              end
            end

            separator
          end
          # newline
          puts
        end
      end
    end
  end
end
