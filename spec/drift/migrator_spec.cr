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

require "sqlite3"

require "../spec_helper"

private def memory_db
  DB.connect "sqlite3:%3Amemory%3A"
end

describe Drift::Migrator do
  describe ".new" do
    it "accepts and existing context" do
      ctx = Drift::Context.new
      migrator = Drift::Migrator.new(memory_db, ctx)

      migrator.context.should be(ctx)
    end

    it "sets a new context based on a given path" do
      migrator = Drift::Migrator.new(memory_db, fixture_path("sequence"))

      migrator.context.ids.should eq([
        20211219152312,
        20211220182717
      ])
    end
  end
end
