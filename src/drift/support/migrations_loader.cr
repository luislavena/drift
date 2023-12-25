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
