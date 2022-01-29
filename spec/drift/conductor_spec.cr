require "../spec_helper"
require "sqlite3"

private def memory_db
  DB.open "sqlite3:%3Amemory%3A"
end

private def loaded_conductor
  conductor = Drift::Conductor.new
  conductor.load_migrations! fixture_path("sequence")

  conductor
end

private def populated_conductor
  conductor = Drift::Conductor.new

  sample_migrations.each do |migration|
    conductor.add migration
  end

  conductor
end

private def quick_migration(id, filename)
  Drift::Migration.new(id.to_i64, filename)
end

private def sample_migrations
  [
    quick_migration(1, "0001_create_users.sql"),
    quick_migration(2, "0002_create_articles.sql"),
    quick_migration(3, "0003_create_tags.sql"),
    quick_migration(4, "0004_create_article_tag.sql"),
  ]
end

describe Drift::Conductor do
  describe "#add" do
    it "allows manually adding migrations to the list" do
      conductor = Drift::Conductor.new

      conductor.migrations.should be_empty

      migration1 = quick_migration(1, "0001_first.sql")
      migration2 = quick_migration(2, "0002_second.sql")
      conductor.add migration1

      conductor.migrations.size.should eq(1)
      conductor.migrations.keys.should eq([1])

      conductor.add migration2
      conductor.migrations.keys.should eq([1, 2])
    end
  end

  describe "#clear" do
    it "clears any loaded migration" do
      conductor = Drift::Conductor.new
      conductor.add quick_migration(1, "0001_first.sql")
      conductor.migrations.size.should eq(1)

      conductor.clear
      conductor.migrations.size.should eq(0)
    end
  end

  describe "#load_migrations!" do
    it "loads all migrations in sequence" do
      conductor = Drift::Conductor.new

      conductor.migrations.size.should eq(0)
      conductor.load_migrations! fixture_path("sequence")

      conductor.migrations.size.should eq(2)
      conductor.migrations.keys.should eq([
        20211219152312_i64,
        20211220182717_i64,
      ])
    end
  end

  describe "#applied?" do
    it "returns false when queried non-applied migration id" do
      db = memory_db
      conductor = populated_conductor

      conductor.applied?(db, 1).should be_false
    end
  end

  describe "#apply" do
    it "applies the given migration once" do
      db = memory_db
      conductor = populated_conductor

      conductor.applied?(db, 1).should be_false

      conductor.apply(db, 1)
      conductor.applied?(db, 1).should be_true

      conductor.apply(db, 1)
      conductor.applied?(db, 1).should be_true
    end

    it "returns the applied batch" do
      db = memory_db
      conductor = populated_conductor

      batch = conductor.apply(db, 1)
      batch.should eq(1)

      batch = conductor.apply(db, 2)
      batch.should eq(2)
    end

    it "gives new batch number after rollback" do
      db = memory_db
      conductor = populated_conductor

      batch_1 = conductor.apply(db, 1)
      batch_2 = conductor.apply(db, 2)

      conductor.rollback(db, 1)

      batch_3 = conductor.apply(db, 1)
      batch_3.should eq(3)
    end
  end

  describe "#apply_batch" do
    it "applies the list of given migrations in a single batch" do
      db = memory_db
      conductor = populated_conductor

      batch = conductor.apply_batch(db, [1, 3])
      batch.should eq(1)

      conductor.applied?(db, 1).should be_true
      conductor.applied?(db, 2).should be_false

      batch = conductor.apply_batch(db, [2, 4])
      batch.should eq(2)

      conductor.applied?(db, 2).should be_true
      conductor.applied?(db, 4).should be_true
    end

    it "skips already applied migrations from the batch" do
      db = memory_db
      conductor = populated_conductor
      conductor.apply(db, 1)

      batch = conductor.apply_batch(db, [1, 2, 3])
      batch.should eq(2)
      conductor.applied?(db, 1).should be_true
      conductor.applied?(db, 2).should be_true
      conductor.applied?(db, 3).should be_true
    end
  end

  describe "#apply_plan" do
    it "returns a list of IDs of migrations to apply" do
      db = memory_db
      conductor = populated_conductor

      plan = conductor.apply_plan(db)
      plan.should eq([
        1,
        2,
        3,
        4,
      ])
    end

    it "excludes already applied migrations from the list" do
      db = memory_db
      conductor = populated_conductor
      conductor.apply(db, 3)

      plan = conductor.apply_plan(db)
      plan.should eq([
        1,
        2,
        4,
      ])
    end
  end

  describe "#rollback" do
    it "rolls back only applied migration" do
      db = memory_db
      conductor = populated_conductor

      conductor.applied?(db, 1).should be_false
      conductor.rollback(db, 1)

      conductor.applied?(db, 1).should be_false
    end

    it "rolls back applied migration" do
      db = memory_db
      conductor = populated_conductor

      conductor.apply(db, 1)
      conductor.applied?(db, 1).should be_true

      conductor.rollback(db, 1)
      conductor.applied?(db, 1).should be_false
    end
  end

  describe "#rollback_batch_plan" do
    it "returns nothing if batch does not exists" do
      db = memory_db
      conductor = populated_conductor

      plan = conductor.rollback_batch_plan(db, 1)
      plan.should be_empty
    end

    it "returns only the list of IDs that needs to be rolled back" do
      db = memory_db
      conductor = populated_conductor

      # batch 1
      batch_1 = conductor.apply_batch(db, [1, 4])

      # batch 2
      batch_2 = conductor.apply_batch(db, [2, 3])

      plan = conductor.rollback_batch_plan(db, batch_1)
      plan.should eq([
        4,
        1,
      ])
    end
  end

  describe "#rollback_plan" do
    it "returns nothing when no migration has to be rolled back" do
      db = memory_db
      conductor = populated_conductor

      plan = conductor.rollback_plan(db)
      plan.should be_empty
    end

    it "returns the list of IDs that needs to be rolled back" do
      db = memory_db
      conductor = populated_conductor

      conductor.apply(db, 1)
      conductor.apply(db, 3)

      plan = conductor.rollback_plan(db)
      plan.should eq([
        3,
        1,
      ])
    end

    it "returns the list of IDs ordered to roll back ordered by batches" do
      db = memory_db
      conductor = populated_conductor
      conductor.apply_batch(db, [1, 4])
      conductor.apply_batch(db, [2, 3])

      plan = conductor.rollback_plan(db)
      plan.should eq([
        3,
        2,
        4,
        1,
      ])
    end
  end

  describe "#status" do
    context "(with empty db)" do
      it "returns all migrations available" do
        db = memory_db
        conductor = populated_conductor

        status = conductor.status(db)
        status.size.should eq(4)

        status.all?(&.applied?).should be_false
      end
    end

    context "(with migrations applied)" do
      it "correctly indicates applied migration" do
        db = memory_db
        conductor = populated_conductor
        conductor.apply_batch(db, [1, 2, 3])

        status = conductor.status(db)
        status.size.should eq(4)
        status.count(&.applied?).should eq(3)
        status.first.applied?.should be_true
        status.last.applied?.should be_false
      end
    end

    context "(with migrations applied but none loaded)" do
      it "correctly list applied migrations" do
        db = memory_db
        conductor = populated_conductor
        conductor.apply_batch(db, [1, 4])
        conductor.clear

        status = conductor.status(db)
        status.size.should eq(2)
        status.map(&.id).should eq([1, 4])
      end
    end
  end
end
