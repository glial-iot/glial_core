#!/usr/bin/env tarantool
local bus = {}
local bus_private = {}

local inspect = require 'libs/inspect'
local clock = require 'clock'
local json = require 'json'
local digest = require 'digest'
local box = box

local scripts_busevents = require 'scripts_busevents'
local scripts_drivers = require 'scripts_drivers'
local system = require 'system'
local fiber = require 'fiber'
local logger = require 'logger'
local config = require 'config'

bus.fifo_saved_rps = 0
bus.bus_saved_rps = 0
bus.max_fifo_count = 0

------------------↓ Private functions ↓------------------

function bus_private.get_value_from_fifo_s()
   local tuple = bus.fifo_storage.index.id:min()
   if (tuple ~= nil) then
      bus.fifo_storage.index.id:delete(tuple['id'])
      local count = bus.fifo_storage.index.id:count()
      if (count > bus.max_fifo_count) then bus.max_fifo_count = count end
      --print("get_value_from_fifo_s:", tuple['topic'], tuple["metadata"], "\n\n")
      return tuple['topic'], tuple["metadata"]
   end
end

function bus_private.fifo_storage_worker()
   while true do
      local topic, metadata = bus_private.get_value_from_fifo_s()
      if (topic ~= nil and metadata ~= nil and type(metadata) == "table") then

         if (metadata.check == true and bus.get_value(topic) == tostring(metadata.value)) then --неправильная логика
            metadata.value = nil
         end

         metadata.time = tonumber(metadata.time/1000/1000) --convert us to seconds
         if (metadata.shadow ~= true and metadata.value ~= nil) then
            scripts_busevents.process(topic, metadata.value, metadata.uuid, metadata.time)
            scripts_drivers.process(topic, metadata.value, metadata.uuid, metadata.time)
         end

         local new_data = {
                           topic,
                           metadata.value or "",
                           metadata.time or 0,
                           metadata.type or "",
                           setmetatable((metadata.tags or {}), {__serialize = 'array'})
                          }

         local update_data = {}
         if (metadata.time ~= nil) then table.insert(update_data, {"=", 3, metadata.time}) end
         if (metadata.value ~= nil) then table.insert(update_data, {"=", 2, metadata.value}) end
         if (metadata.type ~= nil) then table.insert(update_data, {"=", 4, metadata.type}) end
         if (metadata.tags ~= nil) then table.insert(update_data, {"=", 5, metadata.tags}) end

         --print("fifo_storage_worker:\n", inspect(new_data), ",", inspect(update_data))

         bus.storage:upsert(new_data, update_data)
         bus.bus_saved_rps = bus.bus_saved_rps + 1
         fiber.yield()
      else
         fiber.sleep(0.1)
      end
   end
end

function bus_private.bus_rps_stat_worker()
   local cycle_seconds = 5
   fiber.sleep(2)
   while true do
      if (bus.bus_saved_rps >= cycle_seconds*3) then bus.bus_saved_rps = bus.bus_saved_rps - cycle_seconds*3 end
      bus.update{topic = "/glial/bus/fifo_saved", value = bus.fifo_saved_rps/cycle_seconds, type = "record/sec", tags={"system"}}
      bus.update{topic = "/glial/bus/bus_saved", value = bus.bus_saved_rps/cycle_seconds, type = "record/sec", tags={"system"}}
      bus.update{topic = "/glial/bus/fifo_max", value = bus.max_fifo_count, type = "records", tags={"system"}}
      bus.fifo_saved_rps = 0
      bus.bus_saved_rps = 0
      fiber.sleep(cycle_seconds)
   end
end

function bus_private.tags_convert_to_string(table_tags)
   local string_tags = ""
   for i, tag in pairs(table_tags) do
      string_tags = string_tags..tag
      if (i ~= #table_tags) then
         string_tags = string_tags..", "
      end
   end
   return string_tags
end


function bus_private.tags_convert_to_table(tags)
   local processed_tags = tags:gsub("%%20", " ")
   processed_tags = processed_tags:gsub(" ", "")
   local table_tags = {}
   for tag in processed_tags:gmatch("([^,]+)") do
      local copy_flag = false
      for _, table_tag in pairs(table_tags) do
         if (tag == table_tag) then copy_flag = true end
      end
      if (copy_flag == false) then table.insert(table_tags, tag) end
   end
   return table_tags
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

function bus_private.gen_fifo_id(update_time_us)
   local new_id = update_time_us or clock.time64()/1000
   while bus.fifo_storage.index.id:get(new_id) do
      new_id = new_id + 1
   end
   return new_id
end

------------------↓ Public functions ↓------------------

function bus.init()

   ---------↓ Space "storage"(main bus storage) ↓---------
   local format = {
      {name='topic',        type='string'},   --1
      {name='value',        type='string'},   --2
      {name='update_time',  type='number'},   --3
      {name='type',         type='string'},   --4
      {name='tags',         type='array'},    --5
   }
   bus.storage = box.schema.space.create('storage', {if_not_exists = true, format = format, id = config.id.bus})
   bus.storage:create_index('topic', {parts = {'topic'}, if_not_exists = true})


   ---------↓ Space "fifo_storage"(fifo storage) ↓---------
   local fifo_format = {
      {name='id',             type='number'},   --1
      {name='topic',          type='string'},   --2
      {name='metadata',       type='map'},      --3
   }
   bus.fifo_storage = box.schema.space.create('fifo_storage', {if_not_exists = true, temporary = true, format = fifo_format, id = config.id.bus_fifo})
   bus.fifo_storage:create_index('id', {parts={'id'}, if_not_exists = true})


   --------- End storage's config ---------

   fiber.create(bus_private.fifo_storage_worker)
   fiber.create(bus_private.bus_rps_stat_worker)

   local http_system = require 'http_system'
   http_system.endpoint_config("/system_bus", bus.http_api)
end

function bus.update_generator(uuid)
   return function(table)
      if (table == nil) then return false, "No variable" end
      if (type(table) ~= "table") then return false, "Variable not table" end
      if (type(table.topic) ~= "string") then return false, "Not topic variable in table or not string" end

      local id = bus_private.gen_fifo_id()
      local map = setmetatable({}, {__serialize = 'map'})

      table.time = tonumber(table.time)
      if (type(table.value) == "string") then map.value = table.value end
      if (type(table.value) == "number") then map.value = tostring(table.value) end
      if (type(table.value) == "boolean") then map.value = tostring(table.value) end
      if (type(table.type) == "string") then map.type = table.type end
      if (type(uuid) == "string") then map.uuid = uuid end
      if (type(table.tags) == "table") then map.tags = table.tags end
      if (type(table.shadow) == "boolean") then map.shadow = table.shadow end
      if (type(table.check) == "boolean") then map.check = table.check end
      if (type(table.time) == "number") then map.time = table.time else map.time = clock.time64()/1000 end

      bus.fifo_storage:insert{id, table.topic, map}
      bus.fifo_saved_rps = bus.fifo_saved_rps + 1
      return true
   end
end

bus.update = bus.update_generator()

function bus.get_value(topic)
   local tuple = bus.storage.index.topic:get(topic)

   if (tuple ~= nil) then
      return tuple["value"], tuple["update_time"], tuple["type"], setmetatable(tuple["tags"], nil)
   else
      return nil
   end
end

function bus.get_bus(pattern)
   local bus_table = {}

   for _, tuple in bus.storage.index.topic:pairs() do
      local topic = tuple["topic"].."/"

      if (topic:find(pattern or "")) then
         local local_table = {}
         local_table.value = tuple["value"]
         local_table.update_time = tuple["update_time"]
         local_table.topic = tuple["topic"]
         local_table.type = tuple["type"]
         local_table.tags = setmetatable(tuple["tags"], nil)
         table.insert(bus_table, local_table)
      end
   end
   return bus_table
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
         local_table.type = tuple["type"]
         local_table.tags = setmetatable(tuple["tags"], nil)
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
         local_table.__data__.type = tuple["type"]
         local_table.__data__.tags = bus_private.tags_convert_to_string(tuple["tags"])
      end
   end
   return bus_table
end

function bus.http_api(req)
   local params = req:param()
   local return_object

   if (params["action"] == "update_value") then
      if (params["topic"] == nil or params["value"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or value" } }
      else
         local result, err = bus.update{topic = params["topic"], value = params["value"]}
         return_object = req:render{ json = { result = result, err = err } }
      end

   elseif (params["action"] == "update_type") then
      if (params["topic"] == nil or params["type"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or type" } }
      else
         local result, err = bus.update{topic = params["topic"], type = params["type"]}
         return_object = req:render{ json = { result = result, err = err  } }
      end

   elseif (params["action"] == "update_tags") then
      if (params["topic"] == nil or params["tags"] == nil) then
         return_object = req:render{ json = { result = false, msg = "No valid param topic or tags" } }
      else
         local tags_table = bus_private.tags_convert_to_table(params["tags"])
         local result, err = bus.update{topic = params["topic"], tags = tags_table}
         return_object = req:render{ json = { result = result, err = err  } }
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
      for _, tuple in bus.storage.index.topic:pairs() do
         local topic = tuple["topic"]
         local time = tuple["update_time"]
         local value = tuple["value"]
         local type = tuple["type"]
         local tags = bus_private.tags_convert_to_string(tuple["tags"])

         if (params["mask"] ~= nil and params["mask"] ~= "") then
            local mask = "^"..digest.base64_decode(params["mask"]).."$"
            if (string.find(topic, mask) ~= nil) then
               table.insert(data_object, {topic = topic, time = time, value = value, type = type, tags = tags})
            end
         else
            table.insert(data_object, {topic = topic, time = time, value = value, type = type, tags = tags})
         end
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


