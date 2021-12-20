require "./drift/*"

module Drift
  VERSION = {{ `shards version #{__DIR__}`.chomp.stringify }}
end
