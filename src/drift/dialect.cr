# Copyright 2025 Luis Lavena
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

module Drift
  # Raised when an unsupported database dialect is detected
  class UnsupportedDialectError < Error
  end

  # Abstract interface for database-specific SQL operations
  #
  # Each dialect handles the SQL generation and execution for its specific
  # database engine (SQLite3, PostgreSQL, MySQL, etc.)
  abstract struct Dialect
    # Detects the appropriate dialect from a database connection
    def self.from_db(db : DB::Database) : Dialect
      db.using_connection do |conn|
        return from_db(conn)
      end
    end

    # :ditto:
    def self.from_db(conn : DB::Connection) : Dialect
      case conn.class.name
      when .starts_with?("SQLite3")
        SQLite3.new
      else
        raise UnsupportedDialectError.new("Unsupported database: #{conn.class.name}")
      end
    end

    # Check if the migrations table exists in the database
    abstract def prepared?(conn : DB::Connection) : Bool

    # :ditto:
    def prepared?(db : DB::Database) : Bool
      db.using_connection { |conn| prepared?(conn) }
    end

    # Create the migrations tracking table
    abstract def create_schema!(conn : DB::Connection) : Nil

    # :ditto:
    def create_schema!(db : DB::Database) : Nil
      db.using_connection { |conn| create_schema!(conn) }
    end

    # Find a specific migration by *id*, returns the ID if found, nil otherwise
    abstract def find_migration_id(conn : DB::Connection, id : Int64) : Int64?

    # :ditto:
    def find_migration_id(db : DB::Database, id : Int64) : Int64?
      db.using_connection { |conn| find_migration_id(conn, id) }
    end

    # Retrieve all migration IDs from the tracking table
    def all_migration_ids(conn : DB::Connection) : Array(Int64)
      sql_applied_ids = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      conn.query_all(sql_applied_ids, as: Int64)
    end

    # :ditto:
    def all_migration_ids(db : DB::Database) : Array(Int64)
      db.using_connection { |conn| all_migration_ids(conn) }
    end

    # Retrieve all migration IDs in reverse order (batch DESC, id DESC) for
    # reset planning.
    def all_migration_ids_reverse(conn : DB::Connection) : Array(Int64)
      sql_reverse_applied_plan = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          batch DESC,
          id DESC;
        SQL

      conn.query_all(sql_reverse_applied_plan, as: Int64)
    end

    # :ditto:
    def all_migration_ids_reverse(db : DB::Database) : Array(Int64)
      db.using_connection { |conn| all_migration_ids_reverse(conn) }
    end

    # Retrieve all migration entries with full metadata
    def all_migrations(conn : DB::Connection) : Array(Migrator::MigrationEntry)
      sql_all_applied = <<-SQL
        SELECT
          id, batch, applied_at, duration_ns
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      conn.query_all(sql_all_applied, as: Migrator::MigrationEntry)
    end

    # :ditto:
    def all_migrations(db : DB::Database) : Array(Migrator::MigrationEntry)
      db.using_connection { |conn| all_migrations(conn) }
    end

    # Get the maximum batch number from the tracking table, or zero if no batch
    # exists
    def max_batch(conn : DB::Connection) : Int64
      sql_last_batch = <<-SQL
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

      conn.query_one(sql_last_batch, as: Int64)
    end

    # :ditto:
    def max_batch(db : DB::Database) : Int64
      db.using_connection { |conn| max_batch(conn) }
    end

    # Retrieve migration IDs for a specific batch in reverse order (id DESC)
    abstract def batch_migration_ids_reverse(conn : DB::Connection, batch : Int64) : Array(Int64)

    # :ditto:
    def batch_migration_ids_reverse(db : DB::Database, batch : Int64) : Array(Int64)
      db.using_connection { |conn| batch_migration_ids_reverse(conn, batch) }
    end

    # Insert a new migration record into the tracking table
    abstract def insert_migration(conn : DB::Connection, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil

    # :ditto:
    def insert_migration(db : DB::Database, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil
      db.using_connection { |conn| insert_migration(conn, id, batch, applied_at, duration_ns) }
    end

    # Delete a migration record *id* from the tracking table
    abstract def delete_migration(conn : DB::Connection, id : Int64) : Nil

    # :ditto:
    def delete_migration(db : DB::Database, id : Int64) : Nil
      db.using_connection { |conn| delete_migration(conn, id) }
    end
  end
end

require "./dialect/*"
