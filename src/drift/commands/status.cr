require "compiler/crystal/tools/table_print"

require "./command"

module Drift
  module Commands
    class Status < Command
      def run
        migrator = build_migrator
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
