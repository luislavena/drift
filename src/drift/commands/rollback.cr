require "./command"

module Drift
  module Commands
    class Rollback < Command
      def run
        migrator = build_migrator
        check_prepared! migrator

        plan = migrator.rollback_plan

        if plan.empty?
          puts "Nothing to rollback"
          return
        end

        migrator.before_rollback do |id|
          puts "Rolling back: #{migrator.context[id].filename}"
        end

        migrator.after_rollback do |id, span|
          puts "Rolled back:  #{migrator.context[id].filename} (#{human_span(span)})"
        end

        migrator.rollback(plan)
      end
    end
  end
end
