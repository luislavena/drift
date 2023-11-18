require "./command"

module Drift
  module Commands
    class Reset < Command
      def run
        migrator = build_migrator
        check_prepared! migrator

        if migrator.applied_ids.empty?
          puts "Nothing to rollback"
          return
        end

        migrator.before_rollback do |id|
          puts "Rolling back: #{migrator.context[id].filename}"
        end

        migrator.after_rollback do |id, span|
          puts "Rolled back:  #{migrator.context[id].filename} (#{human_span(span)})"
        end

        migrator.reset!
      end
    end
  end
end
