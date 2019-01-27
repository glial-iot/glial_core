#!/usr/bin/env tarantool
local scripts = {}
local scripts_private = {}

local box = box
local uuid_lib = require('uuid')
local fiber = require 'fiber'
local clock = require 'clock'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'

scripts.statuses = {ERROR = "ERROR", WARNING = "WARNING", NORMAL = "NORMAL", STOPPED = "STOPPED"}
scripts.flag = {ACTIVE = "ACTIVE", NON_ACTIVE = "NON_ACTIVE"}
scripts.type = {WEB_EVENT = "WEB_EVENT", TIMER_EVENT = "TIMER_EVENT", SHEDULE_EVENT = "SHEDULE_EVENT", BUS_EVENT = "BUS_EVENT", DRIVER = "DRIVER"}
scripts.store = {}

scripts.worktime_period = 60

------------------↓ Private functions ↓------------------

function scripts_private.worktime_worker()
   for _, tuple in scripts_private.worktime.index.uuid:pairs() do
      scripts_private.worktime.index.uuid:update(tuple["uuid"], {{"=", 2, 0}})
      scripts_private.worktime.index.uuid:update(tuple["uuid"], {{"=", 3, 0}})
   end

   while true do
      fiber.sleep(scripts.worktime_period)
      local worktime_sum = 0.1
      for _, tuple in scripts_private.worktime.index.uuid:pairs() do
         worktime_sum = worktime_sum + (tuple["worktime_ms"] or 0)
      end
      local worktime_percent = worktime_sum / 100
      local alltime_percent = scripts.worktime_period * 1000 / 100

      --local sum_worktime_percents = 0
      --local sum_alltime_percents = 0

      for _, tuple in scripts_private.worktime.index.uuid:pairs() do
         local worktime_ms = tuple["worktime_ms"] or 0
         local worktime_current_percent = (worktime_ms / worktime_percent)
         local alltime_current_percent = (worktime_ms / alltime_percent)

         worktime_current_percent = system.round(worktime_current_percent, 2) or 0
         alltime_current_percent = system.round(alltime_current_percent, 2) or 0

         scripts_private.worktime.index.uuid:update(tuple["uuid"], {{"=", 2, 0}})
         scripts_private.update_specific_data({uuid = tuple["uuid"], worktime_percent = worktime_current_percent})
         scripts_private.update_specific_data({uuid = tuple["uuid"], alltime_percent = alltime_current_percent})

         --sum_alltime_percents = sum_alltime_percents + alltime_current_percent
         --sum_worktime_percents = sum_worktime_percents + worktime_current_percent
         --print(tuple["uuid"], tuple["worktime_ms"], "ms", worktime_current_percent, "%", alltime_current_percent, "%")
      end

      --print(sum_worktime_percents, "%", sum_alltime_percents, "%")

   end
end

------------------↓ Internal API functions ↓------------------


function scripts_private.update_specific_data(data)
   if (data.uuid == nil) then return nil end
   if (scripts_private.storage.index.uuid:select(data.uuid) == nil) then return nil end
   local tuple = scripts_private.storage.index.uuid:get(data.uuid)
   local specific_data = tuple["specific_data"]

   if (data.object ~= nil) then specific_data.object = data.object end
   if (data.alltime_percent ~= nil) then specific_data.alltime_percent = data.alltime_percent end
   if (data.worktime_percent ~= nil) then specific_data.worktime_percent = data.worktime_percent end
   if (data.comment ~= nil) then specific_data.comment = data.comment end
   if (data.tag ~= nil) then specific_data.tag = data.tag end

   specific_data = setmetatable(specific_data, {__serialize = 'map'})
   scripts_private.storage.index.uuid:update(data.uuid, {{"=", 8, specific_data}})
end

function scripts_private.get_list(data)
   local list_table = {}

   for _, tuple in scripts_private.storage.index.type:pairs(data.type) do
      local current_script_table = {
         uuid = tuple["uuid"],
         type = tuple["type"],
         name = tuple["name"],
         status = tuple["status"],
         status_msg = tuple["status_msg"],
         active_flag = tuple["active_flag"],
         object = tuple["specific_data"]["object"],
         worktime_percent = tuple["specific_data"]["worktime_percent"] or 0,
         alltime_percent = tuple["specific_data"]["alltime_percent"] or 0,
         comment = tuple["specific_data"]["comment"] or "",
         tag = tuple["specific_data"]["tag"] or ""
      }
      if (data.tag ~= nil and data.tag ~= "") then
         if (current_script_table.tag == data.tag) then
            table.insert(list_table, current_script_table)
         end
      else
         table.insert(list_table, current_script_table)
      end
   end
   return list_table
end

function scripts_private.get(data)
   local tuple = scripts_private.storage.index.uuid:get(data.uuid)

   if (tuple ~= nil) then
      local table = {
         uuid = tuple["uuid"],
         type = tuple["type"],
         name = tuple["name"],
         body = tuple["body"],
         status = tuple["status"],
         status_msg = tuple["status_msg"],
         active_flag = tuple["active_flag"],
         object = tuple["specific_data"]["object"],
         worktime_percent = tuple["specific_data"]["worktime_percent"] or 0,
         alltime_percent = tuple["specific_data"]["alltime_percent"] or 0,
         comment = tuple["specific_data"]["comment"] or "",
         tag = tuple["specific_data"]["tag"] or ""
      }
      return table
   else
      return nil
   end
end

function scripts_private.update(data)
   if (data.uuid == nil) then return nil end
   if (scripts_private.storage.index.uuid:select(data.uuid) == nil) then return nil end

   if (data.name ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 3, data.name}}) end
   if (data.body ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 4, data.body}}) end
   if (data.status ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 5, data.status}}) end
   if (data.status_msg ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 6, data.status_msg}}) end
   if (data.active_flag ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 7, data.active_flag}}) end

   if (data.object ~= nil) then scripts_private.update_specific_data({uuid = data.uuid, object = data.object}) end
   if (data.comment ~= nil) then scripts_private.update_specific_data({uuid = data.uuid, comment = data.comment}) end
   if (data.tag ~= nil) then scripts_private.update_specific_data({uuid = data.uuid, tag = data.tag}) end

   return scripts_private.get({uuid = data.uuid})
end

function scripts_private.create(data)
   if (data.type == nil) then return nil end
   local new_data = {}
   new_data.uuid = uuid_lib.str()
   new_data.type = data.type
   new_data.name = data.name or data.uuid
   new_data.body = data.body or "\n"
   new_data.status = data.status or scripts.statuses.STOPPED
   new_data.status_msg = data.status_msg or "New script"
   new_data.active_flag = data.active_flag or scripts.flag.NON_ACTIVE
   new_data.specific_data = setmetatable({}, {__serialize = 'map'})

   if (data.object ~= nil) then
      new_data.specific_data.object = data.object
   end

   if (data.comment ~= nil) then
      new_data.specific_data.comment = data.comment
   end

   if (data.tag ~= nil) then
      new_data.specific_data.tag = data.tag
   end

   local table = {
      new_data.uuid,
      new_data.type,
      new_data.name,
      new_data.body,
      new_data.status,
      new_data.status_msg,
      new_data.active_flag,
      new_data.specific_data
   }
   scripts_private.storage:insert(table)
   return scripts_private.get({uuid = new_data.uuid}) or "no." -- зачем тут "no"?
end

function scripts_private.copy(data)
   local tuple_script = scripts_private.storage.index.uuid:get(data.uuid)
   local new_data = {
      type = tuple_script["type"],
      object = tuple_script["specific_data"]["object"],
      name = data.name,
      body = tuple_script["body"]
   }
   local table = scripts_private.create(new_data)
   return true, table, nil
end

function scripts_private.delete(data)
   local script_table = scripts_private.storage.index.uuid:delete(data.uuid)
   if (script_table ~= nil) then
      return true
   else
      return false
   end
end

function scripts_private.storage_init()
   local scripts_storage_format = {
      {name='uuid',           type='string'},   --1
      {name='type',           type='string'},   --2
      {name='name',           type='string'},   --3
      {name='body',           type='string'},   --4
      {name='status',         type='string'},   --5
      {name='status_msg',     type='string'},   --6
      {name='active_flag',    type='string'},   --7
      {name='specific_data',  type='map'}       --8
   }
   scripts_private.storage = box.schema.space.create('scripts', {if_not_exists = true, format = scripts_storage_format, id = config.id.scripts})
   scripts_private.storage:create_index('uuid', {parts = {'uuid'}, if_not_exists = true})
   scripts_private.storage:create_index('type', {parts = {'type'}, if_not_exists = true, unique = false})


   local worktime_format = {
      {name='uuid',              type='string'},   --1
      {name='worktime_ms',       type='number'},   --2
   }
   scripts_private.worktime = box.schema.space.create('worktime', {if_not_exists = true, format = worktime_format, id = config.id.worktime_scripts})
   scripts_private.worktime:create_index('uuid', {parts = {'uuid'}, if_not_exists = true})
end

------------------↓ Public functions ↓------------------

function scripts.generate_fibercreate(uuid, name)
   local function generate_fiber_error_handler(uuid_i, name_i)
      local function fiber_error_handler(msg)
         local trace = debug.traceback("", 2)
         logger.add_entry(logger.WARNING, name_i, msg, uuid_i, trace)
         scripts.update({uuid = uuid_i, status = scripts.statuses.WARNING, status_msg = 'Fiber error: '..(msg or "")})
      end
      return fiber_error_handler
   end
   local error_handler = generate_fiber_error_handler(uuid, name)

   local function fiber_create_modifed(f_function, ...)
      return fiber.create(function(...) return xpcall(f_function, error_handler, ...) end, ...)
   end
   return fiber_create_modifed
end

function scripts.generate_body(script_params, log_script_name)
   local bus = require 'bus'
   local body = setmetatable({}, {__index=_G})
   body.log_error, body.log_warning, body.log_info, body.log_user = logger.generate_log_functions(script_params.uuid, log_script_name)
   body.system_print = body.print
   body.log, body.print = body.log_user, body.log_user
   body.round, body.deepcopy = system.round, system.deepcopy
   body._script_name = script_params.name
   body._script_uuid = script_params.uuid
   body.get_value, body.bus_serialize, body.get_bus = bus.get_value, bus.serialize, bus.get_bus
   body.update = bus.update_generator(script_params.uuid)
   body.fiber = {}
   body.fiber.create = scripts.generate_fibercreate(script_params.uuid, log_script_name)
   body.fiber.sleep, body.fiber.kill, body.fiber.yield, body.fiber.self, body.fiber.status = fiber.sleep, fiber.kill, fiber.yield, fiber.self, fiber.status
   body.http_client = require('http.client').new({1})
   scripts.store[script_params.uuid] = scripts.store[script_params.uuid] or {}
   body.store = scripts.store[script_params.uuid]
   body.main_store = scripts.store
   body.mqtt = require 'mqtt'
   body.json = require 'json'
   body.socket = require 'socket'
   body.clock = require 'clock'
   return body
end

function scripts.safe_mode_error_all()
   local list = scripts_private.get_list({type = nil})

   for _, current_script in pairs(list) do
      logger.add_entry(logger.ERROR, "Script subsystem", 'Script "'..current_script.name..'" not start (safe mode)')
      scripts.update({uuid = current_script.uuid, status = scripts.statuses.ERROR, status_msg = 'Start: safe mode'})
      fiber.yield()
   end
end

function scripts.init()
   scripts_private.storage_init()
   fiber.create(scripts_private.worktime_worker)
end

function scripts.get(data)
   return scripts_private.get({uuid = data.uuid})
end

function scripts.delete(data)
   return scripts_private.delete({uuid = data.uuid})
end

function scripts.get_list(type, tag)
   return scripts_private.get_list({type = type, tag = tag})
end

function scripts.get_tags()
   local tags_table_raw = {}
   local tags_table_processed = {}

   for _, tuple in scripts_private.storage.index.type:pairs() do
      local current_tag = tuple["specific_data"]["tag"]
      if (current_tag ~= nil) then
         tags_table_raw[current_tag] = current_tag
      end
   end

   for _, tag in pairs(tags_table_raw) do
      table.insert(tags_table_processed, tag)
   end

   return tags_table_processed
end

function scripts.copy(name, uuid)
   return scripts_private.copy({name = name, uuid = uuid})
end

function scripts.create(name, type, object, tag, comment, body)
   if (name ~= nil and name ~= "" and type ~= nil and scripts.type[type] ~= nil) then
      local table = scripts_private.create({type = type,
                                            name = name,
                                            object = object,
                                            tag = tag,
                                            comment = comment,
                                            body = body
                                          })
      return true, table
   else
      return false, nil, "Script API Create: no name or type"
   end
end

function scripts.update(data)
   return scripts_private.update(data)
end

function scripts.update_worktime(uuid, time_ms)
   scripts_private.worktime:upsert({uuid, 0}, {{"+", 2, time_ms}})
end

function scripts.get_all(data)
   if (data ~= nil and data.type ~= nil) then
      return scripts_private.get_list({type = data.type})
   else
      return {}
   end
end

return scripts

