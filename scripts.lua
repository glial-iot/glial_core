#!/usr/bin/env tarantool
local scripts = {}
local scripts_private = {}

local box = box
local uuid_lib = require('uuid')
local fiber = require 'fiber'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'

scripts.statuses = {ERROR = "ERROR", WARNING = "WARNING", NORMAL = "NORMAL", STOPPED = "STOPPED"}
scripts.flag = {ACTIVE = "ACTIVE", NON_ACTIVE = "NON_ACTIVE"}
scripts.type = {WEB_EVENT = "WEB_EVENT", TIMER_EVENT = "TIMER_EVENT", SHEDULE_EVENT = "SHEDULE_EVENT", BUS_EVENT = "BUS_EVENT", DRIVER = "DRIVER"}
scripts.store = {}


------------------↓ Private functions ↓------------------

------------------↓ Internal API functions ↓------------------

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
         object = tuple["specific_data"]["object"]
      }
      table.insert(list_table, current_script_table)
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
         object = tuple["specific_data"]["object"]
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

   if (data.object ~= nil) then
      local tuple = scripts_private.storage.index.uuid:get(data.uuid)
      local specific_data = tuple["specific_data"]
      specific_data.object = data.object
      specific_data = setmetatable(specific_data, {__serialize = 'map'})
      scripts_private.storage.index.uuid:update(data.uuid, {{"=", 8, specific_data}})
   end

   return scripts_private.get({uuid = data.uuid})
end

function scripts_private.generate_init_body(type)
   if (type == scripts.type.WEB_EVENT) then
      return [[-- The generated script is filled with the default content --
function http_callback(params, req)

   -- The script will receive parameters in the params table with this kind of query: /we/object?action=print_test
   if (params["action"] == "print_test") then
      return {print_text = "test"}
      --return nil, "OK" --The direct output option without convert to json(see doc on http-tarantool)
   else
      return {no_data = "yes"}
   end
   -- The table returned by the script will be given as json: { "print_text": "test" } or {"no_data": "yes"}

end
]]
   end

   if (type == scripts.type.DRIVER) then
      return [[-- The generated script is filled with the default content --

masks = {"/test/1", "/test/2"}

local function main()
   while true do
      print("Test driver loop")
      fiber.sleep(600)
   end
end

function init()
   store.fiber_object = fiber.create(main)
end

function destroy()
   if (store.fiber_object:status() ~= "dead") then
      store.fiber_object:cancel()
   end
end

function topic_update_callback(value, topic)
   print("Test driver callback:", value, topic)
end]]
   end


   if (type == scripts.type.BUS_EVENT) then
      return [[-- The generated script is filled with the default content --
function event_handler(value, topic)
    store.old_value = store.old_value or 0
    store.old_value = store.old_value + value
    log_info(store.old_value)
end]]
   end

   if (type == scripts.type.TIMER_EVENT) then
      return [[-- The generated script is filled with the default content --
function event_handler()

end]]
   end

   if (type == scripts.type.SHEDULE_EVENT) then
      return [[-- The generated script is filled with the default content --
function event_handler()

end]]
   end

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
   if (data.object ~= nil) then
      local specific_data = {object = data.object}
      new_data.specific_data = setmetatable(specific_data, {__serialize = 'map'})
   else
      new_data.specific_data = setmetatable({}, {__serialize = 'map'})
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
   return scripts_private.get({uuid = new_data.uuid}) or "no."
end

function scripts_private.delete(data)
   local script_table = scripts_private.storage.index.uuid:delete(data.uuid)
   script_table.deleted_status = true
   return script_table
end

function scripts_private.storage_init()
   local format = {
      {name='uuid',           type='string'},   --1
      {name='type',           type='string'},   --2
      {name='name',           type='string'},   --3
      {name='body',           type='string'},   --4
      {name='status',         type='string'},   --5
      {name='status_msg',     type='string'},   --6
      {name='active_flag',    type='string'},   --7
      {name='specific_data',  type='map'}       --8
   }
   scripts_private.storage = box.schema.space.create('scripts', {if_not_exists = true, format = format, id = config.id.scripts})
   scripts_private.storage:create_index('uuid', {parts = {'uuid'}, if_not_exists = true})
   scripts_private.storage:create_index('type', {parts = {'type'}, if_not_exists = true, unique = false})
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
   local uuid_related_set_value = bus.set_value_generator(script_params.uuid)
   body.log_error, body.log_warning, body.log_info, body.log_user = logger.generate_log_functions(script_params.uuid, log_script_name)
   body.system_print = body.print
   body.log, body.print = body.log_user, body.log_user
   body.round, body.deepcopy = system.round, system.deepcopy
   body._script_name = script_params.name
   body._script_uuid = script_params.uuid
   body.set_value, body.shadow_set_value = uuid_related_set_value, bus.shadow_set_value
   body.update_value, body.shadow_update_value = body.set_value, body.shadow_set_value --deprecated names
   body.get_value, body.bus_serialize = bus.get_value, bus.serialize
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
end

function scripts.get(data)
   return scripts_private.get({uuid = data.uuid})
end

function scripts.delete(data)
   return scripts_private.delete({uuid = data.uuid})
end

function scripts.get_list(type)
   return scripts_private.get_list({type = type})
end

function scripts.create(name, type, object)
   if (name ~= nil and name ~= "" and type ~= nil and scripts.type[type] ~= nil) then
      local new_object
      if (object ~= nil) then new_object = string.gsub(object, "+", " ") end
      local table = scripts_private.create({type = type,
                                            name = string.gsub(name, "+", " "),
                                            object = new_object,
                                            body = scripts_private.generate_init_body(type)
                                          })
      return true, table
   else
      return false, nil, "Script API Create: no name or type"
   end
end

function scripts.update(data)
   return scripts_private.update(data)
end

function scripts.get_all(data)
   if (data ~= nil and data.type ~= nil) then
      return scripts_private.get_list({type = data.type})
   else
      return {}
   end
end

return scripts

