require "db"
require "uri"

require "./migration"

module Drift
  struct SchemaMigrationEntry
    include DB::Serializable

    getter id : Int64
    getter batch : Int64
    getter duration_ns : Int64
    getter applied_at : Time?

    def initialize(@id, @batch, @duration_ns, @applied_at = nil)
    end

    def applied?
      !@applied_at.nil?
    end
  end

  class Conductor
    getter migrations : Hash(Int64, Migration)

    def initialize
      @migrations = Hash(Int64, Migration).new
    end

    def add(migration : Migration)
      @migrations[migration.id] = migration
    end

    def applied?(db, id : Int)
      query_migration_applied?(db, id)
    end

    def apply(db, id : Int)
      apply_batch(db, [id])
    end

    def apply_batch(db, ids : Array(Int))
      applied_ids = query_applied_migrations(db).map(&.id)

      batch = query_last_batch(db) + 1
      final_ids = (ids - applied_ids)

      final_ids.each do |id|
        migration = @migrations[id]
        duration = Time.measure { perform_up(db, migration) }

        track_migration(db, id, batch, duration)
      end

      batch
    end

    def apply_plan(db)
      available_ids = @migrations.keys.to_set
      applied_ids = query_applied_migrations(db).map(&.id)

      (available_ids - applied_ids).to_a.sort!
    end

    # clear existing list of migrations
    def clear
      @migrations.clear
    end

    def load_migrations!(path : String | Path)
      clear

      entries = Dir.glob(File.join(path, "*.sql")).sort!

      entries.each do |entry|
        migration = Migration.from_filename(entry)
        add migration
      end
    end

    def rollback(db, id : Int64)
      return unless query_migration_applied?(db, id)

      migration = @migrations[id]

      perform_down(db, migration)
      untrack_migration(db, id)
    end

    def rollback_batch_plan(db, batch : Int64)
      batch_migrations_ids = query_applied_migrations(db).select { |row|
        row.batch == batch
      }.map(&.id)

      batch_migrations_ids.reverse!
    end

    def rollback_plan(db)
      reversed_batch_ids = query_applied_migrations(db).sort_by! { |row|
        {-row.batch, -row.id}
      }.map(&.id)

      reversed_batch_ids
    end

    def status(db)
      # transform Array(SchemaMigrationEntry) to Hash(Int64, SchemaMigrationEntry)
      applied_migrations = Hash(Int64, SchemaMigrationEntry).new
      query_applied_migrations(db).each do |row|
        applied_migrations[row.id] = row
      end

      available_ids = @migrations.keys.to_set
      applied_ids = applied_migrations.keys.to_set

      combined_ids = (available_ids + applied_ids).to_a.sort!

      combined_ids.map { |id|
        if applied_entry = applied_migrations[id]?
          applied_entry
        else
          SchemaMigrationEntry.new(id, 0_i64, 0_i64)
        end
      }
    end

    # FIXME: leaking internals of Drift::Migration
    private def perform_down(db, migration)
      statements = migration.statements_for(:down)
      statements.each do |stmt|
        db.exec stmt
      end
    end

    # FIXME: leaking internals of Drift::Migration
    private def perform_up(db, migration)
      statements = migration.statements_for(:up)
      statements.each do |stmt|
        db.exec stmt
      end
    end

    # TODO: extract and make modular for other adapters
    private def verify_migration_table(db)
      begin
        # try verify migrations table exists
        db.scalar("SELECT COUNT(id) FROM schema_migrations;").as(Int64)
      rescue ex : Exception
        # if not found, create it
        db.exec <<-SQL
          CREATE TABLE IF NOT EXISTS schema_migrations (
              id INTEGER PRIMARY KEY NOT NULL,
              batch INTEGER NOT NULL,
              duration_ns INTEGER NOT NULL,
              applied_at TEXT NOT NULL
          );
          SQL
      end
    end

    private def query_applied_migrations(db)
      verify_migration_table(db)

      db.query_all("SELECT id, batch, duration_ns, applied_at FROM schema_migrations ORDER BY id ASC;", as: SchemaMigrationEntry)
    end

    private def query_last_batch(db)
      verify_migration_table(db)

      db.scalar("SELECT COALESCE(MAX(batch), 0) FROM schema_migrations;").as(Int64)
    end

    private def query_migration_applied?(db, id : Int64)
      verify_migration_table(db)

      retrieved_id = db.query_one?("SELECT id FROM schema_migrations WHERE id = ?;", id, as: Int64)

      retrieved_id == id
    end

    private def track_migration(db, id, batch, duration : Time::Span)
      verify_migration_table(db)

      duration_ns = duration.total_nanoseconds.to_i64
      applied_at = Time.utc

      db.exec "INSERT INTO schema_migrations (id, batch, duration_ns, applied_at) VALUES (?, ?, ?, ?);", id, batch, duration_ns, applied_at
    end

    private def untrack_migration(db, id)
      verify_migration_table(db)

      db.exec "DELETE FROM schema_migrations WHERE id = ?;", id
    end
  end
end
