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

require "db"

require "./migration_entry"

module Drift
  # A `Dialect` owns all the SQL used to track migrations for one database
  # engine. Each method executes a single, complete query against the given
  # database handle; engines that need different SQL override the whole
  # method instead of assembling queries from fragments.
  # The portable queries use `?` placeholders; engines with a different
  # placeholder syntax (like PostgreSQL's `$1`) must override every
  # parameterized method.
  abstract class Dialect
    alias Queriable = DB::Database | DB::Connection

    # Crystal's DB API cannot expose URI or scheme information from a live
    # connection, so the dialect is selected by connection class name.
    def self.from_db(conn : DB::Connection) : Dialect
      case conn.class.name
      when .starts_with?("MySql::")
        Dialects::MySQL.new
      when .starts_with?("PG::")
        Dialects::PostgreSQL.new
      when .starts_with?("SQLite3")
        Dialects::SQLite3.new
      else
        raise UnsupportedDialectError.new("Unsupported database: #{conn.class.name}")
      end
    end

    def self.from_db(db : DB::Database) : Dialect
      db.using_connection do |conn|
        from_db(conn)
      end
    end

    # Creates the `drift_migrations` table used to track applied migrations.
    abstract def create_schema!(db : Queriable) : Nil

    # Returns `true` when the `drift_migrations` table exists.
    abstract def prepared?(db : Queriable) : Bool

    def applied_migrations(db : Queriable) : Array(MigrationEntry)
      sql = <<-SQL
        SELECT
          id, batch, applied_at, duration_ns
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      db.query_all(sql, as: MigrationEntry)
    end

    def applied_ids(db : Queriable) : Array(Int64)
      sql = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      db.query_all(sql, as: Int64)
    end

    def applied?(db : Queriable, id : Int64) : Bool
      sql = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        WHERE
          id = ?
        LIMIT
          1;
        SQL

      db.query_one?(sql, id, as: Int64) == id
    end

    def last_batch(db : Queriable) : Int64
      sql = <<-SQL
        SELECT
          COALESCE(
            MAX(batch),
            0
          )
        FROM
          drift_migrations
        LIMIT
          1;
        SQL

      db.query_one(sql, as: Int64)
    end

    # IDs of every applied migration, last batch first (used by reset).
    def reverse_applied_ids(db : Queriable) : Array(Int64)
      sql = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          batch DESC,
          id DESC;
        SQL

      db.query_all(sql, as: Int64)
    end

    # IDs of one batch, newest migration first (used by rollback).
    def batch_ids(db : Queriable, batch : Int64) : Array(Int64)
      sql = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        WHERE
          batch = ?
        ORDER BY
          id DESC;
        SQL

      db.query_all(sql, batch, as: Int64)
    end

    def insert_migration(db : Queriable, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil
      sql = <<-SQL
        INSERT INTO drift_migrations
          (id, batch, applied_at, duration_ns)
        VALUES
          (?, ?, ?, ?);
        SQL

      db.exec(sql, id, batch, applied_at, duration_ns)
    end

    def delete_migration(db : Queriable, id : Int64) : Nil
      sql = <<-SQL
        DELETE FROM
          drift_migrations
        WHERE
          id = ?;
        SQL

      db.exec(sql, id)
    end
  end
end

require "./dialects/*"
