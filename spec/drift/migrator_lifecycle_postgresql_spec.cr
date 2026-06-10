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

require "../support/migrator_lifecycle"

require "pg"

if pg_url = ENV["POSTGRES_DATABASE_URL"]?
  it_behaves_like_a_migrator("PostgreSQL", Proc(LifecycleDB).new {
    DB.open(pg_url)
  })
else
  describe "Drift::Migrator (PostgreSQL)" do
    pending "set POSTGRES_DATABASE_URL to run against a live server"
  end
end
