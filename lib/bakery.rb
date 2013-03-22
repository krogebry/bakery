##
# The bakery is where we keep the tools used for creating pies.

JSON.create_id = nil

module Bakery
end

require "./lib/bakery/logging.rb"
require "./lib/bakery/hpcloud.rb"
require "./lib/bakery/zone.rb"
require "./lib/bakery/stack.rb"
