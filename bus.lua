#!/usr/bin/env tarantool
local bus = {}
local bus_private = {}

local inspect = require 'libs/inspect'
local clock = require 'clock'
local box = box

local scripts_busevents = require 'scripts_busevents'
local scripts_drivers = require 'scripts_drivers'
local system = require 'system'
local fiber = require 'fiber'
local export = require "exports/export"
local logger = require 'logger'
local config = require 'config'

bus.TYPE = {SHADOW = "SHADOW", NORMAL = "NORMAL"}
bus.check_flag = {CHECK_VALUE = "CHECK_VALUE"}

bus.fifo_saved_rps = 0
bus.bus_saved_rps = 0
bus.max_fifo_count = 0

------------------ Private functions ------------------

function bus_private.tsdb_attr_check_and_save(topic, value)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil and tuple["tsdb"] == "true") then
      export.send_value(topic, value)
   end
end


function bus_private.fifo_storage_worker()
   while true do
      local topic, value, shadow_flag, source_uuid = bus_private.get_value_from_fifo()
      if (value ~= nil and topic ~= nil) then
         if (shadow_flag == bus.TYPE.NORMAL) then
            local new_value = scripts_busevents.process(topic, value, source_uuid)
            value = new_value or value
            scripts_drivers.process(topic, value, source_uuid)
         end
         local timestamp = os.time()
         bus.storage:upsert({topic, value, timestamp, "", {}, "false"}, {{"=", 2, value} , {"=", 3, timestamp}})
         bus.bus_saved_rps = bus.bus_saved_rps + 1
         bus_private.tsdb_attr_check_and_save(topic, value)
         fiber.yield()
      else
         fiber.sleep(0.1)
      end
   end
end

function bus_private.bus_rps_stat_worker()
   fiber.sleep(2)
   while true do
      if (bus.bus_saved_rps >= 15) then bus.bus_saved_rps = bus.bus_saved_rps - 15 end
      bus.set_value("/glue/bus/fifo_saved", bus.fifo_saved_rps/5)
      bus.set_value("/glue/bus/bus_saved", bus.bus_saved_rps/5)
      bus.set_value("/glue/bus/fifo_max", bus.max_fifo_count)
      bus.fifo_saved_rps = 0
      bus.bus_saved_rps = 0
      fiber.sleep(5)
   end
end


function bus_private.add_value_to_fifo(topic, value, shadow_flag, source_uuid)
   if (topic ~= nil and value ~= nil and shadow_flag ~= nil and source_uuid ~= nil) then
      value = tostring(value)
      local id = bus_private.gen_fifo_id()
      bus.fifo_storage:insert{id, topic, value, shadow_flag, source_uuid}
      bus.fifo_saved_rps = bus.fifo_saved_rps + 1
      return true
   end
   return false
end

function bus_private.get_value_from_fifo()
   local tuple = bus.fifo_storage.index.timestamp:min()
   if (tuple ~= nil) then
      bus.fifo_storage.index.timestamp:delete(tuple['timestamp'])
      local count = bus.fifo_storage.index.timestamp:count()
      if (count > bus.max_fifo_count) then bus.max_fifo_count = count end
      return tuple['topic'], tuple["value"], tuple['shadow_flag'], tuple["source_uuid"]
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

function bus_private.update_type(topic, type)
   if (topic ~= nil and type ~= nil and bus.storage.index.topic:get(topic) ~= nil) then
      bus.storage.index.topic:update(topic, {{"=", 4, type}})
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

function bus_private.gen_fifo_id()
   local new_id = clock.realtime()*10000
   while bus.fifo_storage.index.timestamp:get(new_id) do
      new_id = new_id + 1
   end
   return new_id
end

-------------------Public functions-------------------

function bus.init()
   local format = {
      {name='topic',        type='string'},   --1
      {name='value',        type='string'},   --2
      {name='update_time',  type='number'},   --3
      {name='type',         type='string'},   --4
      {name='tags',         type='array'},    --5
      {name='tsdb',         type='string'},   --6
   }
   bus.storage = box.schema.space.create('storage', {if_not_exists = true, format = format, id = config.id.bus})
   bus.storage:create_index('topic', {parts = {'topic'}, if_not_exists = true})



   --------------------------------
   local fifo_format = {
      {name='timestamp',      type='number'},   --1
      {name='topic',          type='string'},   --2
      {name='value',          type='string'},   --3
      {name='shadow_flag',    type='string'},   --4
      {name='source_uuid',    type='string'},   --5
   }
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true, format = fifo_format, id = config.id.bus_fifo})
   bus.fifo_storage:create_index('timestamp', {parts={'timestamp'}, if_not_exists = true})
   --------------------------------

   fiber.create(bus_private.fifo_storage_worker)
   fiber.create(bus_private.bus_rps_stat_worker)

   local http_system = require 'http_system'
   http_system.endpoint_config("/system_bus", bus.http_api_handler)

   bus.storage:upsert({"/glue/bus/fifo_saved", "0", os.time(), "record/sec", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
   bus.storage:upsert({"/glue/bus/bus_saved", "0", os.time(), "record/sec", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
   bus.storage:upsert({"/glue/bus/fifo_max", "0", os.time(), "records", {"system"}, "false"}, {{"=", 2, "0"} , {"=", 3, os.time()}})
end

function bus.set_value_generator(uuid)
   return function(topic, value, check_flag)
      if (check_flag == bus.check_flag.CHECK_VALUE and bus.get_value(topic) ~= tostring(value)) then
         return bus_private.add_value_to_fifo(topic, value, bus.TYPE.NORMAL, uuid)
      end
   end
end

function bus.set_value(topic, value)
   return bus_private.add_value_to_fifo(topic, value, bus.TYPE.NORMAL, "0")
end

function bus.shadow_set_value(topic, value)
   return bus_private.add_value_to_fifo(topic, value, bus.TYPE.SHADOW, "0")
end

function bus.get_value(topic)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil) then
      return tuple["value"], tuple["update_time"], tuple["type"], tuple["tags"]
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
         if (tuple["tsdb"] == "true") then local_table.tsdb = true else local_table.tsdb = false end
         local_table.type = tuple["type"]
         local_table.tags = tuple["tags"]
      end
   end
   return bus_table
end


function bus.serialize_v2(pattern)
   local bus_table = {}

   for _, tuple in bus.storage.index.topic:pairs() do
      local topic = tuple["topic"].."/"
      local subtopic, _, local_table

      if (topic:find(pattern or "")) then
         local_table = bus_table
         repeat
            _, _, subtopic, topic = topic:find("/(.-)(/.*)")
            if (subtopic ~= nil and subtopic ~= "") then
               local_table[subtopic] = local_table[subtopic] or {}
               local_table = local_table[subtopic]
            end
         until subtopic == nil or topic == nil
         local_table.__data__ = {}
         local_table.__data__.value = tuple["value"]
         local_table.__data__.update_time = tuple["update_time"]
         local_table.__data__.topic = tuple["topic"]
         if (tuple["tsdb"] == "true") then local_table.__data__.tsdb = true else local_table.__data__.tsdb = false end
         local_table.__data__.type = tuple["type"]
         local_table.__data__.tags = tuple["tags"]
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
         local result = bus.set_value(params["topic"], params["value"])
         return_object = req:render{ json = { result = result } }
      end

   elseif (params["action"] == "update_type") then
      if (params["topic"] == nil or params["type"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or type" } }
      else
         local result = bus_private.update_type(params["topic"], params["type"])
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

   elseif (params["action"] == "get_bus_serialized_v2") then
      local bus_data = bus.serialize_v2(params["pattern"])
      return_object = req:render{ json = { bus = bus_data } }

   elseif (params["action"] == "get_bus") then
      local data_object = {}
      local current_time = os.time()
      for _, tuple in bus.storage.index.topic:pairs() do
         local text_time
         local topic = tuple["topic"]
         local time = tuple["update_time"]
         local value = tuple["value"]
         local tsdb
         if (tuple["tsdb"] == "true") then tsdb = true else tsdb = false end
         local type = tuple["type"]
         local tags = tuple["tags"]
         local diff_time = current_time - time
         local diff_time_text = system.format_seconds(diff_time)

         if (diff_time > 1) then
            text_time = os.date("%Y-%m-%d, %H:%M:%S", time).." ("..(diff_time_text).." ago)"
         else
            text_time = os.date("%Y-%m-%d, %H:%M:%S", time)
         end
         table.insert(data_object, {topic = topic, text_time = text_time, time = time, value = value, tsdb = tsdb, type = type, tags = tags})
         if (params["limit"] ~= nil and tonumber(params["limit"]) <= #data_object) then break end
      end

      if (#data_object > 0) then
         return_object = req:render{ json =  data_object  }
      else
         return_object = req:render{ json = { none_data = "true" } }
      end

   else
      return_object = req:render{ json = {result = false, error_msg = "Bus API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Bus API: Unknown error(214)"} }
   return system.add_headers(return_object)
end

return bus


