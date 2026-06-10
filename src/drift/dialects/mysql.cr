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
    class MySQL < Dialect
      def create_schema!(db : Queriable) : Nil
        sql = <<-SQL
          CREATE TABLE IF NOT EXISTS drift_migrations (
            id BIGINT PRIMARY KEY NOT NULL,
            batch BIGINT NOT NULL,
            applied_at DATETIME(6) NOT NULL,
            duration_ns BIGINT NOT NULL
          );
          SQL

        db.exec(sql)
      end

      def prepared?(db : Queriable) : Bool
        sql = <<-SQL
          SELECT
            table_name
          FROM
            information_schema.tables
          WHERE
            table_schema = DATABASE()
            AND table_name = 'drift_migrations'
          LIMIT
            1;
          SQL

        db.query_one?(sql, as: String) ? true : false
      end
    end
  end
end
