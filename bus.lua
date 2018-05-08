#!/usr/bin/env tarantool

local log = require 'log'

local bus = {}
local box = box
local scripts_events = require 'scripts_events'
local system = require 'system'
local fifo_storage, fifo_storage_sequence

function bus.events_handler(topic, value)
   for name, item in pairs(scripts_events) do
      if (item.topic ~= nil and item.topic == topic) then
         print("Event "..name.." started on topic "..topic)
         return item.event_function(topic, value)
      end
   end
end

function bus.init()
   fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true})
   fifo_storage_sequence = box.schema.sequence.create("fifo_storage_sequence", {if_not_exists = true})
   fifo_storage:create_index('primary', {sequence="fifo_storage_sequence", if_not_exists = true})
end

function bus.update_value(topic, value)
   local timestamp = os.time()
   local new_value  = bus.events_handler(topic, value)
   fifo_storage:insert{nil, topic, timestamp, (new_value or value)}
end

function bus.get_delete_value()
   local table = fifo_storage.index.primary:select(nil, {iterator = 'EQ', limit = 1})
   local key, topic, timestamp, value
   if (table[1] ~= nil) then
      key = table[1][1]
      topic = table[1][2]
      timestamp = table[1][3]
      value = table[1][4]
      --print("fifo_storage_worker:", key, topic, timestamp, value)
      fifo_storage:delete(key)
   else
      fifo_storage_sequence:reset()
   end
   return key, topic, timestamp, value
end



return bus
