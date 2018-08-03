#!/usr/bin/env tarantool
local bus = {}
local bus_private = {}

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

function bus_private.get_tsdb_attr(topic)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil) then
      if (tuple["tsdb"] ~= nil and tuple["tsdb"] == "true") then
         return true
      end
   end
   return false
end

function bus_private.tsdb_attr_check_and_save(topic, value)
   local tsdb_save = bus_private.get_tsdb_attr(topic)
   if (tsdb_save == true) then
         local answer = influx_storage.update_value("glue", topic, value)
         if (answer ~= nil) then
             logger.add_entry(logger.ERROR, "Influx adapter", 'Influx answer: '..answer)
         end
   end
end


function bus_private.fifo_storage_worker()
   while true do
      local key, topic, update_time, value = bus_private.fifo_get_delete_topics()
      --print("get fifo value:", key, topic, timestamp, value)
      if (key ~= nil) then
         bus.storage:upsert({topic, value, update_time, "", {}, ""}, {{"=", 2, value} , {"=", 3, update_time}})
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
   local update_time = os.time()
   if (topic ~= nil and value ~= nil) then
      local new_value  = scripts_busevents.process(topic, value)
      bus.fifo_storage:insert{nil, topic, tostring((new_value or value)), tonumber(update_time)}
      bus.rps_i = bus.rps_i + 1
      return true
   end
   return false
end

function bus_private.fifo_get_delete_topics() --need refactoring
   local table = bus.fifo_storage.index.primary:select(nil, {iterator = 'EQ', limit = 1})
   local tuple = table[1]
   if (tuple ~= nil) then
       local key = tonumber(tuple['key'])
      local topic = tuple['topic']
      local update_time = tuple['update_time']
      local value = tuple["value"]
      bus.fifo_storage.index.primary:delete(key)
      if (key > bus.max_seq_value) then bus.max_seq_value = key end
      bus.current_key = key
      return key, topic, update_time, value
   else
      if (bus.current_key > 1) then bus.avg_seq_value = bus.current_key end
      bus.fifo_sequence:reset()
   end
end

function bus_private.set_tsdb_save_attribute(topic, value)
   if (value ~= nil and (value == "true" or value == "false")) then
      if (topic == "*") then
         for _, tuple in bus.storage.index.topic:pairs() do
            bus.storage:update(tuple["topic"], {{"=", 6, value}})
         end
      else
         bus.storage.index.topic:update(topic, {{"=", 6, value}})
      end
      return true
   else
      return false
   end
end

function bus_private.delete_topics(topic)
   if (topic ~= nil) then
      if (topic == "*") then
         bus.storage:truncate()
      else
         bus.storage.index.topic:delete(topic)
      end
      return true
   end
   return false
end

-------------------Public functions-------------------

function bus.init()
   local format = {
      {name='topic',        type='string'},   --1
      {name='value',        type='string'},   --2
      {name='update_time',  type='number'},   --3
      {name='type',         type='string'},   --4
      {name='tags',         type='array'},    --5
      {name='tsdb',         type='string'},  --6
   }
   bus.storage = box.schema.space.create('storage', {if_not_exists = true, format = format, id = config.id.bus})
   bus.storage:create_index('topic', {parts = {'topic'}, if_not_exists = true})



   --------------------------------
   local fifo_format = {
      {name='key',            type='integer'},   --1
      {name='topic',          type='string'},   --2
      {name='value',          type='string'},   --3
      {name='update_time',    type='number'},   --4
   }
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true, format = fifo_format, id = config.id.bus_fifo})
   bus.fifo_sequence = box.schema.sequence.create("fifo_storage_sequence", {if_not_exists = true})
   bus.fifo_storage:create_index('primary', {sequence="fifo_storage_sequence", if_not_exists = true})

   bus_private.fifo_storage_worker_fiber = fiber.create(bus_private.fifo_storage_worker)
   bus_private.bus_rps_stat_worker_fiber = fiber.create(bus_private.bus_rps_stat_worker)

   local http_system = require 'http_system'
   http_system.endpoint_config("/system_bus", bus.http_api_handler)
end


function bus.update_value(topic, value) -- external value name (incorrect)
   local result = bus_private.add_value_to_fifo_buffer(topic, value)
   return result
end

function bus.get_value(topic)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil) then
      return tuple["value"]
   else
      return nil
   end
end

function bus.serialize(pattern)
   local bus_table = {}

   for _, tuple in bus.storage.index.topic:pairs() do
      local topic = tuple["topic"].."/"
      local subtopic, _, local_table

      if (topic:find(pattern or "")) then
         local_table = bus_table
         repeat
            _, _, subtopic, topic = topic:find("/(.-)(/.*)")
            if (subtopic ~= nil) then
               local_table[subtopic] = local_table[subtopic] or {}
               local_table = local_table[subtopic]
            end
         until subtopic == nil or topic == nil
         local_table.value = tuple["value"]
         local_table.update_time = tuple["update_time"]
         local_table.topic = tuple["topic"]
         local_table.tsdb = tuple["tsdb"]
         local_table.type = tuple["type"]
         local_table.tags = tuple["tags"]
      end
   end
   return bus_table
end

function bus.http_api_handler(req)
   local params = req:param()
   local return_object

   if (params["action"] == "update_tsdb_attribute") then
      if (params["value"] == "true" or params["value"] == "false") then
         if (params["topic"] ~= nil) then
            local result = bus_private.set_tsdb_save_attribute(params["topic"], params["value"])
            return_object = req:render{ json = { result = result } }
         else
         return_object = req:render{ json = { result = false, msg = "No valid param topic" } }
         end
      else
         return_object = req:render{ json = { result = false, msg = "No valid param value" } }
      end

   elseif (params["action"] == "update_value") then
      if (params["topic"] == nil or params["value"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or value" } }
      else
         local result = bus.update_value(params["topic"], params["value"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "delete_topics") then
      if (params["topic"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic" } }
      else
         local result = bus_private.delete_topics(params["topic"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "get_bus_serialized") then
      local bus_data = bus.serialize(params["pattern"])
      return_object = req:render{ json = { bus = bus_data } }

   elseif (params["action"] == "get_bus") then
      local data_object = {}
      local current_time = os.time()
      for _, tuple in bus.storage.index.topic:pairs() do
         local text_time
         local topic = tuple["topic"]
         local update_time = tuple["update_time"]
         local value = tuple["value"]
         local tsdb
         if (tuple["tsdb"] == "false") then tsdb = false else tsdb = true end
         local type = tuple["type"]
         local tags = tuple["tags"]
         local diff_time = current_time - update_time
         local diff_time_text = system.format_seconds(diff_time)

         if (diff_time > 1) then
            text_time = os.date("%Y-%m-%d, %H:%M:%S", update_time).." ("..(diff_time_text).." ago)"
         else
            text_time = os.date("%Y-%m-%d, %H:%M:%S", update_time)
         end
         table.insert(data_object, {topic = topic, text_time = text_time, time = update_time, value = value, tsdb = (tsdb or false), type = type, tags = tags})
         if (params["limit"] ~= nil and tonumber(params["limit"]) <= #data_object) then break end
      end

      if (#data_object > 0) then
         return_object = req:render{ json =  data_object  }
      else
         return_object = req:render{ json = { none_data = "true" } }
      end

   else
      return_object = req:render{ json = {error = true, error_msg = "Bus API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Bus API: Unknown error(214)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

return bus


