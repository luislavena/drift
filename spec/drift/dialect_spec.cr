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

describe Drift::Dialect do
  describe ".from_db" do
    it "detects SQLite3 dialect" do
      db = DB.open("sqlite3:%3Amemory%3A")
      dialect = Drift::Dialect.from_db(db)

      dialect.should be_a(Drift::Dialect::SQLite3)

      db.close
    end
  end
end
