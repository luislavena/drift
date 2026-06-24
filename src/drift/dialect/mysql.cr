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
  class Dialect
    class MySQL < Dialect
      def prepare!(db) : Nil
        db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS #{Dialect::TABLE} (
            id BIGINT NOT NULL PRIMARY KEY,
            batch BIGINT NOT NULL,
            applied_at DATETIME(6) NOT NULL,
            duration_ns BIGINT NOT NULL
          );
        SQL
      end

      def prepared?(db) : Bool
        found = db.query_one?(<<-SQL, as: Int64)
          SELECT
            1
          FROM
            information_schema.tables
          WHERE
            table_schema = DATABASE()
            AND table_name = '#{Dialect::TABLE}'
          LIMIT
            1;
        SQL
        !found.nil?
      end

      def applied?(db, id : Int64) : Bool
        found = db.query_one?(<<-SQL, id, as: Int64)
          SELECT
            id
          FROM
            #{Dialect::TABLE}
          WHERE
            id = ?
          LIMIT
            1;
        SQL
        found == id
      end

      def applied_ids(db) : Array(Int64)
        db.query_all(<<-SQL, as: Int64)
          SELECT
            id
          FROM
            #{Dialect::TABLE}
          ORDER BY
            id ASC;
        SQL
      end

      def applied_entries(db) : Array(Drift::Migrator::MigrationEntry)
        db.query_all(<<-SQL, as: Drift::Migrator::MigrationEntry)
          SELECT
            id, batch, applied_at, duration_ns
          FROM
            #{Dialect::TABLE}
          ORDER BY
            id ASC;
        SQL
      end

      def last_batch(db) : Int64
        db.query_one(<<-SQL, as: Int64)
          SELECT
            COALESCE(
              MAX(batch),
              0
            )
          FROM
            #{Dialect::TABLE}
          LIMIT
            1;
        SQL
      end

      def ids_in_batch(db, batch : Int64) : Array(Int64)
        db.query_all(<<-SQL, batch, as: Int64)
          SELECT
            id
          FROM
            #{Dialect::TABLE}
          WHERE
            batch = ?
          ORDER BY
            id DESC;
        SQL
      end

      def applied_ids_desc(db) : Array(Int64)
        db.query_all(<<-SQL, as: Int64)
          SELECT
            id
          FROM
            #{Dialect::TABLE}
          ORDER BY
            batch DESC,
            id DESC;
        SQL
      end

      def record!(cnn : DB::Connection, id : Int64, batch : Int64, applied_at : Time, duration_ns : Int64) : Nil
        cnn.exec(<<-SQL, id, batch, applied_at, duration_ns)
          INSERT INTO #{Dialect::TABLE}
            (id, batch, applied_at, duration_ns)
          VALUES
            (?, ?, ?, ?);
        SQL
      end

      def forget(cnn : DB::Connection, id : Int64) : Nil
        cnn.exec(<<-SQL, id)
          DELETE FROM
            #{Dialect::TABLE}
          WHERE
            id = ?;
        SQL
      end
    end
  end
end
