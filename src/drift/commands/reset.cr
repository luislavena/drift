# Copyright 2023 Luis Lavena
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

require "./command"

module Drift
  module Commands
    class Reset < Command
      def run
        migrator = build_migrator
        check_prepared! migrator

        if migrator.applied_ids.empty?
          puts "Nothing to rollback"
          return
        end

        migrator.before_rollback do |id|
          puts "Rolling back: #{migrator.context[id].filename}"
        end

        migrator.after_rollback do |id, span|
          puts "Rolled back:  #{migrator.context[id].filename} (#{human_span(span)})"
        end

        migrator.reset!
      end
    end
  end
end
