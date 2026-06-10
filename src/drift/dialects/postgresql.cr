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

require "../dialect"

module Drift
  module Dialects
    class PostgreSQL < Dialect
      def create_schema!(db : Queriable) : Nil
        sql = <<-SQL
          CREATE TABLE IF NOT EXISTS drift_migrations (
            id BIGINT PRIMARY KEY NOT NULL,
            batch BIGINT NOT NULL,
            applied_at TIMESTAMPTZ NOT NULL,
            duration_ns BIGINT NOT NULL
          );
          SQL

        db.exec(sql)
      end

      def prepared?(db : Queriable) : Bool
        sql = <<-SQL
          SELECT
            EXISTS (
              SELECT
                1
              FROM
                information_schema.tables
              WHERE
                table_schema = current_schema()
                AND table_name = 'drift_migrations'
            );
          SQL

        db.query_one(sql, as: Bool)
      end

      def applied?(db : Queriable, id : Int64) : Bool
        sql = <<-SQL
          SELECT
            id
          FROM
            drift_migrations
          WHERE
            id = $1
          LIMIT
            1;
          SQL

        db.query_one?(sql, id, as: Int64) == id
      end

      def batch_ids(db : Queriable, batch : Int64) : Array(Int64)
        sql = <<-SQL
          SELECT
            id
          FROM
            drift_migrations
          WHERE
            batch = $1
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
            ($1, $2, $3, $4);
          SQL

        db.exec(sql, id, batch, applied_at, duration_ns)
      end

      def delete_migration(db : Queriable, id : Int64) : Nil
        sql = <<-SQL
          DELETE FROM
            drift_migrations
          WHERE
            id = $1;
          SQL

        db.exec(sql, id)
      end
    end
  end
end
