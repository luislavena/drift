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

module Drift
  module Adapters
    class SQLite3 < Adapter
      def create_schema
        sql_create_schema = <<-SQL
          CREATE TABLE IF NOT EXISTS drift_migrations (
            id INTEGER PRIMARY KEY NOT NULL,
            batch INTEGER NOT NULL,
            applied_at TEXT NOT NULL,
            duration_ns INTEGER NOT NULL
          );
          SQL

        db.transaction do |tx|
          cnn = tx.connection
          cnn.exec(sql_create_schema)
        end
      end

      def schema_exists?
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

        db.query_one?(sql_check_schema, as: String) ? true : false
      end

      def track_migration(id : Int64, batch : Int64, duration : Time::Span)
        sql_track_migration = <<-SQL
          INSERT INTO drift_migrations
            (id, batch, applied_at, duration_ns)
          VALUES
            (?, ?, ?, ?);
          SQL

        applied_at = Time.utc
        duration_ns = duration.total_nanoseconds.to_i64

        db.exec(sql_track_migration, id, batch, applied_at, duration_ns)
      end

      def untrack_migration(id : Int64)
        sql_untrack_migration = <<-SQL
          DELETE FROM
            drift_migrations
          WHERE
            id = ?;
          SQL

        db.exec(sql_untrack_migration, id)
      end
    end
  end
end
