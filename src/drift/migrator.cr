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
require "./dialect"
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
    getter dialect : Dialect

    alias BeforeCallback = Proc(Int64, Nil)
    alias AfterCallback = Proc(Int64, Time::Span, Nil)

    @before_apply = Array(BeforeCallback).new
    @after_apply = Array(AfterCallback).new

    @before_rollback = Array(BeforeCallback).new
    @after_rollback = Array(AfterCallback).new

    def initialize(@db, @context)
      @dialect = resolve_dialect(@db)
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
      entries = @dialect.applied_entries(@db)
      current_applied_ids = applied_ids

      entries.reject! { |e| !e.id.in?(current_applied_ids) }
    end

    def applied?(id : Int64) : Bool
      @dialect.applied?(@db, id)
    end

    def applied_ids
      result_ids = Set.new(@dialect.applied_ids(@db))

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
      @dialect.prepare!(@db)
    end

    def prepared? : Bool
      @dialect.prepared?(@db)
    end

    def reset!
      rollback_batch(reset_plan)
    end

    def reset_plan
      batch_ids = Set.new(@dialect.applied_ids_desc(@db))

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
      last_batch = @dialect.last_batch(@db)
      batch_ids = Set.new(@dialect.ids_in_batch(@db, last_batch))

      (batch_ids & Set{*context.ids}).to_a
    end

    private def resolve_dialect(db) : Dialect
      case db
      when DB::Connection
        Dialect.from_db(db)
      else
        db.using_connection { |cnn| Dialect.from_db(cnn) }
      end
    end

    private def apply_batch(ids : Array(Int64))
      plan_ids = Set{*ids} - Set{*applied_ids}

      db.transaction do |tx|
        cnn = tx.connection
        batch = @dialect.last_batch(cnn) + 1

        plan_ids.each do |id|
          migration = context[id]

          # trigger before_apply callbacks
          @before_apply.each &.call(id)

          duration = Time.measure { migration.run(:up, cnn) }
          applied_at = Time.utc
          duration_ns = duration.total_nanoseconds.to_i64

          @dialect.record!(cnn, id, batch, applied_at, duration_ns)

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

          @dialect.forget(cnn, id)

          @after_rollback.each &.call(id, duration)
        end
      end
    end
  end
end
