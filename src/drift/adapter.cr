# Copyright 2022 Luis Lavena
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

require "db"
require "uri"

module Drift
  abstract class Adapter
    private getter db : DB::Database | DB::Connection

    abstract def create_schema
    abstract def schema_exists?
    abstract def track_migration(id : Int64, batch : Int64, duration : Time::Span)
    abstract def untrack_migration(id : Int64)

    def initialize(@db)
    end

    def self.for(connection : DB::Connection)
      klass = klass_for(connection.context.uri)
      klass.new(connection)
    end

    def self.for(db : DB::Database)
      klass = klass_for(db.uri)
      klass.new(db)
    end

    def self.klass_for(uri : URI)
      case uri.scheme
      when "sqlite3"
        Adapters::SQLite3
      else
        raise ArgumentError.new(%{no adapter found for scheme "#{uri.scheme}"})
      end
    end
  end
end

require "./adapters/*"
