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

require "sqlite3"

describe Drift::Adapter do
  describe ".klass_for(URI)" do
    it "correctly maps to a SQLite3 adapter class" do
      klass = Drift::Adapter.klass_for(URI.parse("sqlite3:%3Amemory%3A"))
      klass.should be_a(Drift::Adapters::SQLite3.class)
    end

    it "fails to map for unsupported adapter" do
      expect_raises(ArgumentError, /no adapter found for scheme "fake"/) do
        Drift::Adapter.klass_for(URI.parse("fake://user:pass@server/db"))
      end
    end
  end

  describe ".for(DB)" do
    it "correctly identifies and wraps a DB instance" do
      adapter = Drift::Adapter.for(DB.open("sqlite3:%3Amemory%3A"))
      adapter.should be_a(Drift::Adapters::SQLite3)
    end

    it "correctly identifies and wraps a DB connection" do
      adapter = Drift::Adapter.for(DB.connect("sqlite3:%3Amemory%3A"))
      adapter.should be_a(Drift::Adapters::SQLite3)
    end
  end
end
