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

require "./dialect"

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
    getter db : DB::Database

    alias BeforeCallback = Proc(Int64, Nil)
    alias AfterCallback = Proc(Int64, Time::Span, Nil)

    @before_apply = Array(BeforeCallback).new
    @after_apply = Array(AfterCallback).new

    @before_rollback = Array(BeforeCallback).new
    @after_rollback = Array(AfterCallback).new

    @dialect : Dialect

    def initialize(@db, @context)
      @dialect = Dialect.from_db(@db)
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
      entries = @dialect.all_migrations(db)
      current_applied_ids = applied_ids

      entries.reject! { |e| !e.id.in?(current_applied_ids) }
    end

    def applied?(id : Int64) : Bool
      query_id = @dialect.find_migration_id(db, id)

      query_id == id
    end

    def applied_ids
      result_ids = Set{*@dialect.all_migration_ids(db)}
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
      db.transaction do |tx|
        cnn = tx.connection
        @dialect.create_schema!(cnn)
      end
    end

    def prepared? : Bool
      @dialect.prepared?(db)
    end

    def reset!
      rollback_batch(reset_plan)
    end

    def reset_plan
      batch_ids = Set{*@dialect.all_migration_ids_reverse(db)}
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
      last_batch = @dialect.max_batch(db)

      # Get migration IDs for last batch in reverse order
      batch_ids = @dialect.batch_migration_ids_reverse(db, last_batch)

      (Set{*batch_ids} & Set{*context.ids}).to_a
    end

    private def apply_batch(ids : Array(Int64))
      plan_ids = Set{*ids} - Set{*applied_ids}

      db.transaction do |tx|
        cnn = tx.connection
        batch = @dialect.max_batch(cnn) + 1

        plan_ids.each do |id|
          migration = context[id]

          # trigger before_apply callbacks
          @before_apply.each &.call(id)

          duration = Time.measure { migration.run(:up, cnn) }
          applied_at = Time.utc
          duration_ns = duration.total_nanoseconds.to_i64

          @dialect.insert_migration(cnn, id, batch, applied_at, duration_ns)

          # trigger after_apply callbacks
          @after_apply.each &.call(id, duration)
        end
      end
    end

    private def rollback_batch(ids : Array(Int64))
      plan_ids = Set{*ids} & Set{*applied_ids}

      db.transaction do |tx|
        cnn = tx.connection

        plan_ids.each do |id|
          migration = context[id]

          @before_rollback.each &.call(id)

          duration = Time.measure { migration.run(:down, cnn) }

          @dialect.delete_migration(cnn, id)

          @after_rollback.each &.call(id, duration)
        end
      end
    end
  end
end
