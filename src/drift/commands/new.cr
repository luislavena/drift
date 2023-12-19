require "./command"

module Drift
  module Commands
    class New < Command
      MIGRATION_TEMPLATE = <<-SQL
      -- drift:up

      -- drift:down
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
