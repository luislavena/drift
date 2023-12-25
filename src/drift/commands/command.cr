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

require "option_parser"
require "uri"

require "db"

module Drift
  module Commands
    class Options
      property migrations_path : String = Drift::MIGRATIONS_PATH
      property db_url : URI? { ENV["DB_URL"]?.try { |uri| URI.parse(uri) } }

      def self.from_parser(parser : OptionParser)
        options = Options.new

        parser.on("--db URI", "-d URI", "URI for the database") do |value|
          options.db_url = URI.parse(value)
        end

        parser.on("--path DIR", "Directory that contains migration files") do |value|
          options.migrations_path = value
        end

        options
      end
    end

    abstract class Command
      getter options : Options

      def self.run(options, *args)
        new(options).run(*args)
      end

      def initialize(@options)
      end

      private def check_prepared!(migrator : Drift::Migrator)
        raise Drift::Error.new("No migration table found.") unless migrator.prepared?
      end

      private def human_span(span : Time::Span)
        total_milliseconds = span.total_milliseconds
        if total_milliseconds < 1
          return "#{(span.total_milliseconds * 1_000).round.to_i}μs"
        end

        total_seconds = span.total_seconds
        if total_seconds < 1
          return "#{span.total_milliseconds.round(2)}ms"
        end

        if total_seconds < 60
          return "#{total_seconds.round(2)}s"
        end

        minutes = span.minutes
        seconds = span.seconds

        "#{minutes}m #{seconds}s"
      end

      private def with_migrator
        if uri = options.db_url
          DB.open(uri) do |db|
            yield Drift::Migrator.from_path(db, options.migrations_path)
          end
        else
          raise Drift::Error.new("A database is required.") unless uri
        end
      end
    end
  end
end
