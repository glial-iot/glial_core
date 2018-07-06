#!/usr/bin/env tarantool
local bus = {}
local bus_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box

local scripts_busevents = require 'scripts_busevents'
local system = require 'system'
local fiber = require 'fiber'
local influx_storage = require "tsdb_drivers/influx_storage"
local logger = require 'logger'
local config = require 'config'

bus.rps_i = 0
bus.rps_o = 0
bus.max_seq_value = 0
bus.avg_seq_value = 0
bus.current_key = 0

------------------ Private functions ------------------

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
      local new_value  = scripts_busevents.process(topic, value)
      bus.fifo_storage:insert{nil, topic, timestamp, (new_value or value)}
      bus.rps_i = bus.rps_i + 1
   end
end

function bus_private.fifo_get_delete_topics() --need refactoring
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

function bus.init() --need refactoring
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true, id = config.id.bus_fifo})
   bus.fifo_sequence = box.schema.sequence.create("fifo_storage_sequence", {if_not_exists = true})
   bus.fifo_storage:create_index('primary', {sequence="fifo_storage_sequence", if_not_exists = true})

   bus.bus_storage = box.schema.space.create('bus_storage', {if_not_exists = true, id = config.id.bus})
   bus.bus_storage:create_index('topic', {parts = {1, 'string'}, if_not_exists = true})

   bus_private.fifo_storage_worker_fiber = fiber.create(bus_private.fifo_storage_worker)
   bus_private.bus_rps_stat_worker_fiber = fiber.create(bus_private.bus_rps_stat_worker)

   local http_system = require 'http_system'
   http_system.endpoint_config("/system_bus_data", bus.http_data_handler)
   http_system.endpoint_config("/system_bus_action", bus.action_data_handler)
end


function bus.update_value(topic, value) -- external value name (incorrect)
   bus_private.add_value_to_fifo_buffer(topic, value)
end


function bus.get_value(topic)
      local tuple = bus.bus_storage.index.topic:get(topic)

      if (tuple ~= nil) then
         return tuple[3]
      else
         return nil
      end
   end

function bus.action_data_handler(req)
   local params = req:param()

   if (params["action"] == "update_tsdb_attribute") then
      if (params["value"] == "true") then
         params["value"] = true
      elseif (params["value"] == "false") then
         params["value"] = false
      else
         return req:render{ json = { result = false } }
      end
      bus_private.set_tsdb_save_attribute(params["topic"], params["value"])

   elseif (params["action"] == "update_value") then
      if (params["topic"] == nil or params["value"] == nil) then
         return req:render{ json = { result = false } }
      end
      bus.update_value(params["topic"], params["value"])

   elseif (params["action"] == "delete_topics") then
      if (params["topic"] == nil) then
         return req:render{ json = { result = false } }
      end
      bus_private.delete_topics(params["topic"])
   end
   local return_object = req:render{ json = { result = true } }

   return_object = return_object or req:render{ json = {error = true, error_msg = "Bus API: Unknown error(214)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

function bus.http_data_handler(req) --move to actions
   local params = req:param()
   local return_object
   local data_object = {}
   local current_time = os.time()
   --Database struct: 1(topic), 2(timestamp), 3(value), 4(tsdb_save)
   for _, tuple in bus.bus_storage.index.topic:pairs() do
      local processed_timestamp
      local topic = tuple[1]
      local timestamp = tuple[2]
      local value = tuple[3]
      local tsdb_save = tuple[4]
      local diff_time = current_time - timestamp
      local diff_time_text = system.format_seconds(diff_time)
      if (diff_time > 1) then
         processed_timestamp = os.date("%Y-%m-%d, %H:%M:%S", timestamp).." ("..(diff_time_text).." ago)"
      else
         processed_timestamp = os.date("%Y-%m-%d, %H:%M:%S", timestamp)
      end
      table.insert(data_object, {topic = topic, timestamp = processed_timestamp, value = value, tsdb_save = (tsdb_save or false)})
      if (params["limit"] ~= nil and tonumber(params["limit"]) <= #data_object) then break end
   end

   if (#data_object > 0) then
      return_object = req:render{ json =  data_object  }
   else
      return_object = req:render{ json = { none_data = "true" } }
   end


   return_object = return_object or req:render{ json = {error = true, error_msg = "Bus API: Unknown error(215)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';

   return return_object
end

return bus


