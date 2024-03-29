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

module Drift
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}

  # :nodoc:
  ID_PATTERN = /(^[0-9]+)/

  # Default migrations location
  MIGRATIONS_PATH = "database/migrations"

  # :nodoc:
  class Error < Exception
  end

  # :nodoc:
  class MigrationError < Error
  end

  # :nodoc:
  class ContextError < Error
  end

  def self.extract_id?(filename : String) : Int64?
    # extract ID from filename
    (ID_PATTERN.match(File.basename(filename)).try &.[1]).try &.to_i64
  end
end

require "./drift/*"
