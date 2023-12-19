require "option_parser"

require "./drift"
require "./drift/commands/*"

require "sqlite3"

module Drift
  class CLI
    @args : Array(String)

    def self.run(args = ARGV)
      new(args).run
    end

    def initialize(@args)
    end

    def display_help(opts)
      puts <<-HELP
        Usage: drift [<command>]

        Commands:
            help                             Show this page (default)
            migrate                          Apply migrations
            new <migration>                  Create a new migration file
            reset                            Rollback all applied migrations
            rollback                         Rollback last migration batch
            status                           Display current migrations status
            version                          Show application version

        General options:
        HELP
      puts opts
    end

    def run
      options = uninitialized Commands::Options

      parser = OptionParser.new do |opt|
        options = Commands::Options.from_parser(opt)

        opt.unknown_args do |args|
          case args[0]?
          when "migrate"
            Commands::Migrate.run(options)
          when "new"
            Commands::New.run(options, args[1]?)
          when "reset"
            Commands::Reset.run(options)
          when "rollback"
            Commands::Rollback.run(options)
          when "status"
            Commands::Status.run(options)
          when "version"
            puts "Drift v#{Drift::VERSION}"
          else
            display_help(opt)
          end
        end
      end

      parser.parse(@args)
    end
  end
end

begin
  Drift::CLI.run
rescue ex : Drift::Error
  STDERR.puts "ERROR: #{ex.message}"
  exit 1
end
