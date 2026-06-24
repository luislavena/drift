# Copyright 2026 Luis Lavena
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

module Drift
  class UnsupportedDialectError < Error
  end

  # A dialect owns the SQL and execution for Drift's bookkeeping table.
  #
  # Read methods accept either a `DB::Database` or a `DB::Connection`.
  # `record!` and `forget` require a `DB::Connection` because they run inside
  # a migrator transaction.
  abstract class Dialect
    TABLE = "drift_migrations"

    abstract def prepare!(db : DB::Database | DB::Connection) : Nil
    abstract def prepared?(db : DB::Database | DB::Connection) : Bool
    abstract def applied?(db : DB::Database | DB::Connection, id : Int64) : Bool
    abstract def applied_ids(db : DB::Database | DB::Connection) : Array(Int64)
    abstract def applied_entries(db : DB::Database | DB::Connection) : Array(Drift::Migrator::MigrationEntry)
    abstract def last_batch(db : DB::Database | DB::Connection) : Int64
    abstract def ids_in_batch(db : DB::Database | DB::Connection, batch : Int64) : Array(Int64)
    abstract def applied_ids_desc(db : DB::Database | DB::Connection) : Array(Int64)
    abstract def record!(cnn : DB::Connection, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil
    abstract def forget(cnn : DB::Connection, id : Int64) : Nil

    # Resolve a dialect by inspecting the connection's class name. crystal-db
    # cannot report the URI or schema of a connection, so the driver's
    # namespace is the only signal available.
    def self.from_db(conn : DB::Connection) : Dialect
      case conn.class.name
      when .starts_with?("SQLite3")
        Dialect::SQLite3.new
      else
        raise UnsupportedDialectError.new("Unsupported database: #{conn.class.name}")
      end
    end
  end
end

require "./dialect/*"
