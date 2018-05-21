#!/usr/bin/env tarantool

local log = require 'log'
local inspect = require 'libs/inspect'

local logger = require 'logger'

local bus = {}
local bus_private = {}
local box = box
local scripts_events = require 'scripts_events'
local system = require 'system'

local fiber = require 'fiber'
local influx_storage = require "tsdb_drivers/influx_storage"


bus.rps_i = 0
bus.rps_o = 0
bus.max_seq_value = 0
bus.avg_seq_value = 0
bus.current_key = 0

function bus_private.events_handler(topic, value)
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

function bus_private.get_tsdb_save_attribute(topic)
   local table = bus.bus_storage.index.topic:select(topic, {iterator = 'EQ', limit = 1})
   if (table[1] ~= nil) then
      local tsdb_save = table[1][4]
      if (tsdb_save ~= nil and tsdb_save == true) then
         return true
      end
   end
   return false
end

function bus_private.tsdb_attr_check_and_save(topic, value)
   local tsdb_save = bus_private.get_tsdb_save_attribute(topic)
   if (tsdb_save == true) then
         local answer = influx_storage.update_value("glue", topic, value)
         if (answer ~= nil) then
             logger.add_entry(logger.ERROR, "Influx adapter", 'Influx answer: '..answer)
         end
   end
end


function bus_private.fifo_storage_worker()
   while true do
      local key, topic, timestamp, value = bus_private.fifo_get_delete_topics()
      --print("get fifo value:", key, topic, timestamp, value)
      if (key ~= nil) then
         bus.bus_storage:upsert({topic, timestamp, value}, {{"=", 2, timestamp} , {"=", 3, value}})
         bus.rps_o = bus.rps_o + 1
         bus_private.tsdb_attr_check_and_save(topic, value)
         fiber.yield()
      else
         fiber.sleep(0.1)
      end
   end
end

function bus_private.bus_rps_stat_worker()
   while true do
      bus.update_value("/glue/rps_i", bus.rps_i)
      bus.update_value("/glue/rps_o", bus.rps_o)
      bus.rps_i = 0
      bus.rps_o = 0
      fiber.sleep(1)
   end
end


function bus_private.add_value_to_fifo_buffer(topic, value)
   local timestamp = os.time()
   if (topic ~= nil and value ~= nil) then
      local new_value  = bus_private.events_handler(topic, value)
      bus.fifo_storage:insert{nil, topic, timestamp, (new_value or value)}
      bus.rps_i = bus.rps_i + 1
   end
end

function bus_private.fifo_get_delete_topics()
   local table = bus.fifo_storage.index.primary:select(nil, {iterator = 'EQ', limit = 1})
   local key, topic, timestamp, value
   if (table[1] ~= nil) then
      key = table[1][1]
      topic = table[1][2]
      timestamp = table[1][3]
      value = table[1][4]
      bus.fifo_storage:delete(key)
      if (key > bus.max_seq_value) then bus.max_seq_value = key end
      bus.current_key = key
      return key, topic, timestamp, value
   else
      if (bus.current_key > 1) then bus.avg_seq_value = bus.current_key end
      bus.fifo_sequence:reset()
   end
end

function bus_private.set_tsdb_save_attribute(topic, value)
   if (value ~= nil and (value == true or value == false)) then
      if (topic == "*") then
         for _, tuple in bus.bus_storage.index.topic:pairs() do
            local current_topic = tuple[1]
            bus.bus_storage:update(current_topic, {{"=", 4, value}})
         end
      else
         bus.bus_storage:update(topic, {{"=", 4, value}})
      end
   end
end

function bus_private.delete_topics(topic)
   if (topic ~= nil) then
      if (topic == "*") then
         bus.bus_storage:truncate()
      else
         bus.bus_storage.index.topic:delete(topic)
      end
   end
end


-------------------Public functions-------------------

function bus.init()
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true})
   bus.fifo_sequence = box.schema.sequence.create("fifo_storage_sequence", {if_not_exists = true})
   bus.fifo_storage:create_index('primary', {sequence="fifo_storage_sequence", if_not_exists = true})

   bus.bus_storage = box.schema.space.create('bus_storage', {if_not_exists = true})
   bus.bus_storage:create_index('topic', {parts = {1, 'string'}, if_not_exists = true})

   bus_private.fifo_storage_worker_fiber = fiber.create(bus_private.fifo_storage_worker)
   bus_private.bus_rps_stat_worker_fiber = fiber.create(bus_private.bus_rps_stat_worker)
end

function bus.update_value(topic, value) -- external value name (incorrect)
   bus_private.add_value_to_fifo_buffer(topic, value)
end

function bus.action_data_handler(req)
   local param_action, param_topic, param_value = req:param("action"), req:param("topic"), req:param("value")

   if (param_action == "update_tsdb_attribute") then
      if (param_value == "true") then
         param_value = true
      elseif (param_value == "false") then
         param_value = false
      else
         return req:render{ json = { result = false } }
      end
      bus_private.set_tsdb_save_attribute(param_topic, param_value)

   elseif (param_action == "update_value") then
      if (param_topic == nil or param_value == nil) then
         return req:render{ json = { result = false } }
      end
      bus.update_value(param_topic, param_value)

   elseif (param_action == "delete_topics") then
      if (param_topic == nil) then
         return req:render{ json = { result = false } }
      end
      bus_private.delete_topics(param_topic)
   end

   return req:render{ json = { result = true } }
end

function bus.http_data_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local current_time = os.time()
   --Database struct: 1(topic), 2(timestamp), 3(value), 4(tsdb_save)
   for _, tuple in bus.bus_storage.index.topic:pairs() do
      i = i + 1
      data_object[i] = {}
      data_object[i].topic = tuple[1]
      local diff_time_raw = current_time - tuple[2]
      local diff_time_text = system.format_seconds(diff_time_raw)
      if (diff_time_raw > 1) then
         data_object[i].timestamp = os.date("%Y-%m-%d, %H:%M:%S", tuple[2]).." ("..(diff_time_text).." ago)"
      else
         data_object[i].timestamp = os.date("%Y-%m-%d, %H:%M:%S", tuple[2])
      end
      data_object[i].value = tuple[3]
      data_object[i].tsdb_save = tuple[4] or false
      if (type_limit ~= nil and type_limit <= i) then break end
   end

   if (i > 0) then
      return_object = req:render{ json =  data_object  }
   else
      return_object = req:render{ json = { none_data = "true" } }
   end

   return return_object
end

return bus


