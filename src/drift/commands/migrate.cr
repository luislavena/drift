require "./command"

module Drift
  module Commands
    class Migrate < Command
      def run
        migrator = build_migrator
        migrator.prepare! unless migrator.prepared?

        if migrator.pending?
          migrator.before_apply do |id|
            puts "Migrating: #{migrator.context[id].filename}"
          end

          migrator.after_apply do |id, span|
            puts "Migrated:  #{migrator.context[id].filename} (#{human_span(span)})"
          end

          migrator.apply!
        else
          puts "Nothing to migrate"
        end
      end
    end
  end
end
