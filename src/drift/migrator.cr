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

require "./context"
require "db"

module Drift
  class Migrator
    class MigrationEntry
      include DB::Serializable

      getter id : Int64
      getter batch : Int64
      getter duration_ns : Int64
      getter applied_at : Time

      def duration
        Time::Span.new(nanoseconds: duration_ns)
      end
    end

    getter context : Context
    getter db : DB::Database | DB::Connection

    alias BeforeCallback = Proc(Int64, Nil)
    alias AfterCallback = Proc(Int64, Time::Span, Nil)

    @before_apply = Array(BeforeCallback).new
    @after_apply = Array(AfterCallback).new

    @before_rollback = Array(BeforeCallback).new
    @after_rollback = Array(AfterCallback).new

    def initialize(@db, @context)
    end

    def self.from_path(db, path : String)
      ctx = Context.new
      ctx.load_path(path)

      new(db, ctx)
    end

    def after_apply(&proc : AfterCallback)
      @after_apply.push proc
    end

    def after_rollback(&proc : AfterCallback)
      @after_rollback.push proc
    end

    def applied : Array(MigrationEntry)
      sql_all_applied = <<-SQL
        SELECT
          id, batch, applied_at, duration_ns
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      entries = db.query_all(sql_all_applied, as: MigrationEntry)
      current_applied_ids = applied_ids

      entries.reject! { |e| !e.id.in?(current_applied_ids) }
    end

    def applied?(id : Int64) : Bool
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

      query_id = db.query_one?(sql_find_migration_id, id, as: Int64)

      query_id == id
    end

    def applied_ids
      sql_applied_ids = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          id ASC;
        SQL

      result_ids = Set{*db.query_all(sql_applied_ids, as: Int64)}
      (result_ids & Set{*context.ids}).to_a
    end

    def apply(id : Int64)
      apply_batch([id])
    end

    def apply(*ids : Int64)
      apply_batch(ids.to_a)
    end

    def apply!
      prepare!
      apply_batch(apply_plan)
    end

    def apply_plan
      (context.ids - applied_ids)
    end

    def before_apply(&proc : BeforeCallback)
      @before_apply.push proc
    end

    def before_rollback(&proc : BeforeCallback)
      @before_rollback.push proc
    end

    def pending?
      !(context.ids - applied_ids).empty?
    end

    def prepare!
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

    def prepared? : Bool
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

    def reset!
      rollback_batch(reset_plan)
    end

    def reset_plan
      sql_reverse_applied_plan = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        ORDER BY
          batch DESC,
          id DESC;
        SQL

      batch_ids = Set{*db.query_all(sql_reverse_applied_plan, as: Int64)}
      (batch_ids & Set{*context.ids}).to_a
    end

    def rollback(id : Int64)
      rollback_batch([id])
    end

    def rollback(*ids : Int64)
      rollback_batch(ids.to_a)
    end

    def rollback(ids : Array(Int64))
      rollback_batch(ids)
    end

    def rollback_plan
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

      last_batch = db.query_one(sql_last_batch, as: Int64)

      sql_reverse_applied_batch = <<-SQL
        SELECT
          id
        FROM
          drift_migrations
        WHERE
          batch = ?
        ORDER BY
          id DESC;
        SQL

      batch_ids = Set{*db.query_all(sql_reverse_applied_batch, last_batch, as: Int64)}
      (batch_ids & Set{*context.ids}).to_a
    end

    private def apply_batch(ids : Array(Int64))
      plan_ids = Set{*ids} - Set{*applied_ids}

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

      sql_insert_migration = <<-SQL
        INSERT INTO drift_migrations
          (id, batch, applied_at, duration_ns)
        VALUES
          (?, ?, ?, ?);
        SQL

      db.transaction do |tx|
        cnn = tx.connection
        batch = cnn.query_one(sql_last_batch, as: Int64) + 1

        plan_ids.each do |id|
          migration = context[id]

          # trigger before_apply callbacks
          @before_apply.each &.call(id)

          duration = Time.measure { migration.run(:migrate, cnn) }
          applied_at = Time.utc
          duration_ns = duration.total_nanoseconds.to_i64

          cnn.exec(sql_insert_migration, id, batch, applied_at, duration_ns)

          # trigger after_apply callbacks
          @after_apply.each &.call(id, duration)
        end
      end
    end

    private def rollback_batch(ids : Array(Int64))
      plan_ids = Set{*ids} & Set{*applied_ids}

      sql_delete_migration = <<-SQL
        DELETE FROM
          drift_migrations
        WHERE
          id = ?;
        SQL

      db.transaction do |tx|
        cnn = tx.connection

        plan_ids.each do |id|
          migration = context[id]

          @before_rollback.each &.call(id)

          duration = Time.measure { migration.run(:rollback, cnn) }

          cnn.exec(sql_delete_migration, id)

          @after_rollback.each &.call(id, duration)
        end
      end
    end
  end
end
