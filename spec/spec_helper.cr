require "spec"
require "../src/drift"

def fixture_path(*paths : String)
  File.join(__DIR__, "fixtures", *paths)
end
