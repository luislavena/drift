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

require "../spec_helper"

describe Drift::Context do
  describe ".new" do
    it "can be populated with multiple migrations" do
      mig_a = Drift::Migration.new(1)
      mig_b = Drift::Migration.new(2)

      ctx = Drift::Context.new
      ctx.should be_empty

      ctx.add mig_a
      ctx.add mig_b

      ctx.should_not be_empty
    end
  end

  describe "#ids" do
    it "returns the available migrations, ordered" do
      ctx = Drift::Context.new
      ctx.add Drift::Migration.new(2)
      ctx.add Drift::Migration.new(1)

      ctx.ids.should eq([1, 2])
    end
  end

  describe "#load_path" do
    it "populates list of found migrations" do
      ctx = Drift::Context.new
      ctx.load_path fixture_path("sequence")

      ctx.should_not be_empty
      ctx.ids.should eq([
        20211219152312,
        20211220182717,
      ])
    end
  end

  describe "#[]?" do
    context "(empty)" do
      it "returns nothing for non existing migration" do
        ctx = Drift::Context.new
        mig = ctx[1]?

        mig.should be_nil
      end
    end

    context "(manually added)" do
      it "returns loaded migration" do
        mig_a = Drift::Migration.new(1)

        ctx = Drift::Context.new
        ctx.add mig_a

        ctx[1]?.should eq(mig_a)
      end
    end

    context "(loaded from path)" do
      it "loads the respective migration" do
        ctx = Drift::Context.new
        ctx.load_path fixture_path("sequence")

        if migration = ctx[20211219152312]?
          migration.should be_a(Drift::Migration)
          migration.id.should eq(20211219152312)

          if filename = migration.filename
            filename.should contain("20211219152312_create_humans")
          else
            # expected failure branch
            typeof(filename).should be_a(String)
          end
        else
          # expected failure branch
          typeof(migration).should be_a(Drift::Migration)
        end
      end
    end
  end

  describe "#[]" do
    it "raises when referenced migration does not exists" do
      ctx = Drift::Context.new

      expect_raises(Drift::ContextError, /Missing migration/) do
        ctx[1]
      end
    end
  end
end
