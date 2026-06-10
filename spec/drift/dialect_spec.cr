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

require "../spec_helper"

require "sqlite3"
require "mysql"
require "pg"

# A connection class crystal-db accepts but no Drift dialect knows about,
# used to exercise the UnsupportedDialectError path without a server.
private class BogusConnection < DB::Connection
  def initialize
    super(DB::Connection::Options.new)
  end

  def build_prepared_statement(query) : DB::Statement
    raise NotImplementedError.new("build_prepared_statement")
  end

  def build_unprepared_statement(query) : DB::Statement
    raise NotImplementedError.new("build_unprepared_statement")
  end
end

describe Drift::Dialect do
  describe ".from_db" do
    it "returns SQLite3 dialect for a SQLite connection" do
      conn = DB.connect "sqlite3:%3Amemory%3A"
      begin
        Drift::Dialect.from_db(conn).should be_a(Drift::Dialects::SQLite3)
      ensure
        conn.close
      end
    end

    it "returns SQLite3 dialect for a SQLite database pool" do
      db = DB.open "sqlite3:%3Amemory%3A"
      begin
        Drift::Dialect.from_db(db).should be_a(Drift::Dialects::SQLite3)
      ensure
        db.close
      end
    end

    it "raises UnsupportedDialectError for unknown connection classes" do
      expect_raises(Drift::UnsupportedDialectError, /BogusConnection/) do
        Drift::Dialect.from_db(BogusConnection.new)
      end
    end
  end
end

if mysql_url = ENV["MYSQL_DATABASE_URL"]?
  describe Drift::Dialect do
    it "returns MySQL dialect for a MySQL connection" do
      db = DB.open(mysql_url)
      begin
        Drift::Dialect.from_db(db).should be_a(Drift::Dialects::MySQL)
      ensure
        db.close
      end
    end
  end
else
  describe Drift::Dialect do
    pending "MySQL dialect selection (set MYSQL_DATABASE_URL to run)"
  end
end

if pg_url = ENV["POSTGRES_DATABASE_URL"]?
  describe Drift::Dialect do
    it "returns PostgreSQL dialect for a PostgreSQL connection" do
      db = DB.open(pg_url)
      begin
        Drift::Dialect.from_db(db).should be_a(Drift::Dialects::PostgreSQL)
      ensure
        db.close
      end
    end
  end
else
  describe Drift::Dialect do
    pending "PostgreSQL dialect selection (set POSTGRES_DATABASE_URL to run)"
  end
end
