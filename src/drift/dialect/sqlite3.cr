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

module Drift
  struct Dialect
    # SQLite3-compatible SQL implementation
    struct SQLite3 < Dialect
      def prepared?(conn : DB::Connection) : Bool
        sql_check_schema = <<-SQL
          SELECT
            name
          FROM
            sqlite_schema
          WHERE
            type = "table"
            AND name = "drift_migrations"
          LIMIT
            1;
          SQL

        conn.query_one?(sql_check_schema, as: String) ? true : false
      end

      def create_schema!(conn : DB::Connection) : Nil
        sql_create_schema = <<-SQL
          CREATE TABLE IF NOT EXISTS drift_migrations (
            id INTEGER PRIMARY KEY NOT NULL,
            batch INTEGER NOT NULL,
            applied_at TEXT NOT NULL,
            duration_ns INTEGER NOT NULL
          );
          SQL

        conn.exec(sql_create_schema)
      end

      def find_migration_id(conn : DB::Connection, id : Int64) : Int64?
        sql_find_migration_id = <<-SQL
          SELECT
            id
          FROM
            drift_migrations
          WHERE
            id = ?
          LIMIT
            1;
          SQL

        conn.query_one?(sql_find_migration_id, id, as: Int64)
      end

      def batch_migration_ids_reverse(conn : DB::Connection, batch : Int64) : Array(Int64)
        sql_batch_ids_reverse = <<-SQL
          SELECT
            id
          FROM
            drift_migrations
          WHERE
            batch = ?
          ORDER BY
            id DESC;
          SQL

        conn.query_all(sql_batch_ids_reverse, batch, as: Int64)
      end

      def insert_migration(conn : DB::Connection, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil
        sql_insert_migration = <<-SQL
          INSERT INTO drift_migrations
            (id, batch, applied_at, duration_ns)
          VALUES
            (?, ?, ?, ?);
          SQL

        conn.exec(sql_insert_migration, id, batch, applied_at, duration_ns)
      end

      def delete_migration(conn : DB::Connection, id : Int64) : Nil
        sql_delete_migration = <<-SQL
          DELETE FROM
            drift_migrations
          WHERE
            id = ?;
          SQL

        conn.exec(sql_delete_migration, id)
      end
    end
  end
end
