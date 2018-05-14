#!/usr/bin/env tarantool

local log = require 'log'
local inspect = require 'inspect'

local logger = require 'logger'

local bus = {}
local box = box
local scripts_events = require 'scripts_events'
local system = require 'system'

local fiber = require 'fiber'
local ts_storage = require 'ts_storage'
local influx_storage = require "influx_storage"


bus.rps_i = 0
bus.rps_o = 0
bus.max_key_value = 0
local average_data = {}

function bus.events_handler(topic, value)
   for name, item in pairs(scripts_events) do
      if (item ~= nil and type(item) == "table" and item.topic ~= nil and item.topic == topic) then
         --print("Event "..name.." started on topic "..topic)
         local status, data = pcall(item.event_function, topic, value)
         if (status == true) then
            return data
         else
            logger.add_entry(logger.ERROR, "Events subsystem", 'Event "'..item.name..'" run failed (internal error: '..(data or "")..')')
         end
      end
   end
end

function bus.fifo_storage_worker()
   while true do
      local key, topic, timestamp, value = bus.get_delete_value()
      print("get fifo value:", key, topic, timestamp, value)
      if (key ~= nil) then
         bus.bus_storage:upsert({topic, timestamp, value}, {{"=", 2, timestamp} , {"=", 3, value}})
         bus.rps_o = bus.rps_o + 1
         local answer = influx_storage.handler("glue", topic, value)
         if (answer ~= nil) then print(answer) end
         fiber.yield()
      else
         fiber.sleep(0.1)
      end
   end
end

function bus.bus_rps_stat_worker()
   while true do
      bus.update_value("/glue/rps_i", bus.rps_i)
      bus.update_value("/glue/rps_o", bus.rps_o)
      bus.rps_i = 0
      bus.rps_o = 0
      fiber.sleep(1)

      --print(inspect(fiber.info()))
   end
end


function bus.init()
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true})
   bus.fifo_sequence = box.schema.sequence.create("fifo_storage_sequence", {if_not_exists = true})
   bus.fifo_storage:create_index('primary', {sequence="fifo_storage_sequence", if_not_exists = true})

   bus.bus_storage = box.schema.space.create('bus_storage', {if_not_exists = true, temporary = true})
   bus.bus_storage:create_index('topic', {parts = {1, 'string'}, if_not_exists = true})

   bus.fifo_storage_worker_fiber = fiber.create(bus.fifo_storage_worker)
   bus.bus_rps_stat_worker_fiber = fiber.create(bus.bus_rps_stat_worker)
end

function bus.update_value(topic, value)
   local timestamp = os.time()
   local new_value  = bus.events_handler(topic, value)
   bus.fifo_storage:insert{nil, topic, timestamp, (new_value or value)}
   bus.rps_i = bus.rps_i + 1
end

function bus.update_value_average(topic, value, period)
   local timestamp = os.time()
   value = bus.events_handler(topic, value) or value
   if (average_data[topic] == nil) then average_data[topic] = {} end
   if (average_data[topic].data == nil) then average_data[topic].data = {} end
   if (average_data[topic].timestamp == nil) then average_data[topic].timestamp = timestamp + period end

   if (average_data[topic].timestamp < timestamp) then
      local summ_value, average_value = 0
      for i, local_value in pairs(average_data[topic].data) do
         summ_value = summ_value + local_value
      end
      local all_count = #average_data[topic].data
      if (tonumber(all_count) == 0) then
         average_value = system.round(value, 3)
      else
         average_value = system.round((summ_value / all_count), 3)
         timestamp = math.floor((average_data[topic].timestamp + timestamp)/2)
      end

      bus.fifo_storage:insert{nil, topic, timestamp, average_value}
      --print("average(topic "..topic..") calc: "..average_value)
      average_data[topic].timestamp = timestamp + period
      average_data[topic].data = nil
      average_data[topic].data = {}
   else
      average_data[topic].data[#average_data[topic].data+1] = value
      --print("average(topic "..topic..") add: "..value)
   end
end

function bus.get_delete_value()
   local table = bus.fifo_storage.index.primary:select(nil, {iterator = 'EQ', limit = 1})
   local key, topic, timestamp, value
   if (table[1] ~= nil) then
      key = table[1][1]
      topic = table[1][2]
      timestamp = table[1][3]
      value = table[1][4]
      bus.fifo_storage:delete(key)
      if (key > bus.max_key_value) then bus.max_key_value = key end
      return key, topic, timestamp, value
   else
      bus.fifo_sequence:reset()
   end
end



return bus
