#!/usr/bin/env tarantool
local scripts = {}
local scripts_private = {}

local box = box
local uuid_lib = require('uuid')
local digest = require 'digest'
local fiber = require 'fiber'
local http_client = require('http.client').new({50})


local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'

scripts.statuses = {ERROR = "ERROR", WARNING = "WARNING", NORMAL = "NORMAL", STOPPED = "STOPPED"}
scripts.flag = {ACTIVE = "ACTIVE", NON_ACTIVE = "NON_ACTIVE"}
scripts.type = {WEB_EVENT = "WEB_EVENT", TIMER_EVENT = "TIMER_EVENT", SHEDULE_EVENT = "SHEDULE_EVENT", BUS_EVENT = "BUS_EVENT", DRIVER = "DRIVER"}
scripts.store = {}


------------------ Private functions ------------------

------------------ Internal API functions ------------------

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

topics = {"/test/1", "/test/2"}

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
   return scripts_private.storage.index.uuid:delete(data.uuid)
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

function scripts_private.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/scripts", scripts_private.http_api)
   http_system.endpoint_config("/scripts_body", scripts_private.http_api_body)
end

------------------ HTTP API functions ------------------


function scripts_private.http_api_get_list(params, req)
   local table = scripts_private.get_list({type = params["type"]})
   return req:render{ json = table }
end


function scripts_private.http_api_create(params, req)
   if (params["name"] ~= nil and params["name"] ~= "" and params["type"] ~= nil and scripts.type[params["type"]] ~= nil) then
      local table = scripts_private.create({type = params["type"],
                                            name = params["name"],
                                            status = params["status"],
                                            status_msg = params["status_msg"],
                                            object = params["object"],
                                            body = scripts_private.generate_init_body(params["type"])
                                          })
      return req:render{ json = table }
   else
      return req:render{ json = {result = false, error_msg = "Script API Create: no name or type"} }
   end
end


function scripts_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts_private.get({uuid = params["uuid"]}) ~= nil) then
         local table = scripts_private.delete({uuid = params["uuid"]})
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Script API Delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Script API Delete: no UUID"} }
   end
end


function scripts_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts_private.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Script API Get: no UUID"} }
   end
end


function scripts_private.http_api_update(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts_private.get({uuid = params["uuid"]}) ~= nil) then
         local data = {}
         data.uuid = params["uuid"]
         data.name = params["name"]
         data.active_flag = params["active_flag"]
         data.object = params["object"]
         local table = scripts_private.update(data)
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Script API Update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Script API Update: no UUID"} }
   end
end


function scripts_private.http_api_body(req)
   local return_object

   local uuid = req:query_param().uuid
   local post_params = req:post_param()
   local text_base64 = pairs(post_params)(post_params)
   local text_decoded
   local data = {}
   local _,_, base_64_string = string.find(text_base64 or "", "data:text/plain;base64,(.+)")
   if (base_64_string ~= nil) then
      text_decoded = digest.base64_decode(base_64_string)
   end
   if (uuid ~= nil and text_decoded ~= nil) then
      data.uuid = uuid
      data.body = text_decoded
      if (scripts_private.get({uuid = uuid}) ~= nil) then
         local table = scripts_private.update(data)
         return_object = req:render{ json = table }
      else
         return_object = req:render{ json = {result = false, error_msg = "Script API Body update: UUID not found"} }
      end
   else
      return_object = req:render{ json = {result = false, error_msg = "Script API Body update: no UUID or no body"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Script API Body update: Unknown error(1213)"} }
   return system.add_headers(return_object)
end


function scripts_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "get_list") then
      return_object = scripts_private.http_api_get_list(params, req)

   elseif (params["action"] == "create") then
      return_object = scripts_private.http_api_create(params, req)

   elseif (params["action"] == "delete") then
      return_object = scripts_private.http_api_delete(params, req)

   elseif (params["action"] == "get") then
      return_object = scripts_private.http_api_get(params, req)

   elseif (params["action"] == "update") then
      return_object = scripts_private.http_api_update(params, req)

   else
      return_object = req:render{ json = {result = false, error_msg = "Script API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Script API: Unknown error(213)"} }
   return system.add_headers(return_object)
end

------------------ Public functions ------------------

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
   local uuid_related_update_value = bus.update_value_genarator(script_params.uuid)
   body.log_error, body.log_warning, body.log_info, body.log_user = logger.generate_log_functions(script_params.uuid, log_script_name)
   body.system_print = body.print
   body.log, body.print = body.log_user, body.log_user
   body._script_name = script_params.name
   body._script_uuid = script_params.uuid
   body.update_value, body.shadow_update_value, body.get_value, body.bus_serialize = uuid_related_update_value, bus.shadow_update_value, bus.get_value, bus.serialize
   body.fiber = {}
   body.fiber.create = scripts.generate_fibercreate(script_params.uuid, log_script_name)
   body.fiber.sleep, body.fiber.kill, body.fiber.yield, body.fiber.self, body.fiber.status = fiber.sleep, fiber.kill, fiber.yield, fiber.self, fiber.status
   body.http_client = http_client
   scripts.store[script_params.uuid] = scripts.store[script_params.uuid] or {}
   body.store = scripts.store[script_params.uuid]
   return body
end


function scripts.init()
   scripts_private.storage_init()
   scripts_private.http_init()
end

function scripts.get(data)
   return scripts_private.get({uuid = data.uuid})
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

