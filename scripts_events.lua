#!/usr/bin/env tarantool
local log = require 'log'
local logger = require 'logger'
local system = require "system"
local inspect = require 'libs/inspect'

local scripts_events = {}

scripts_events.vaisala_event = {}
scripts_events.vaisala_event.topic = "/vaisala/H2S"
function scripts_events.vaisala_event.event_function(topic, value)
   --local bus = require 'bus'
   --bus.update_value(topic.."_x100", value*100)
end

return scripts_events
