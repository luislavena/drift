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

require "mysql"

if mysql_url = ENV["MYSQL_DATABASE_URL"]?
  it_behaves_like_a_migrator("MySQL", Proc(LifecycleDB).new {
    DB.open(mysql_url)
  })
else
  describe "Drift::Migrator (MySQL)" do
    pending "set MYSQL_DATABASE_URL to run against a live server"
  end
end
