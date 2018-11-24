#!/usr/bin/env tarantool
local bus_events = {}
local bus_events_private = {}

local box = box
local http_system = require 'http_system'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local fiber = require 'fiber'
local digest = require 'digest'

local bus_events_main_scripts_table = {}

bus_events_private.init_body = [[-- The generated script is filled with the default content --
function event_handler(value, topic, timestamp)
    store.old_value = store.old_value or 0
    store.old_value = store.old_value + value
    log_info(store.old_value)
end]]

local function log_bus_events_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Bus-events subsystem", msg, uuid, "")
end

local function log_bus_events_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Bus-events subsystem", msg, uuid, "")
end

local function log_bus_events_info(msg, uuid)
   logger.add_entry(logger.INFO, "Bus-events subsystem", msg, uuid, "")
end

------------------↓ Private functions ↓------------------


function bus_events_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_bus_events_error('Attempt to start non-busevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: not found'})
      return false
   end

   if (script_params.body == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: no body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      --log_bus_events_info('Web-event "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Bus event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, err_msg = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_bus_events_error('Bus-event "'..script_params.name..'" not start (load error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(err_msg or "")})
      return false
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_bus_events_error('Bus-event "'..script_params.name..'" not start ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: "event_handler" function not found or no function'})
      return false
   end

   if ((script_params.object == nil or script_params.object == "") and type(script_params.object) == "string") then
      log_bus_events_error('Bus-event "'..script_params.name..'" not start (mask not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: mask not found'})
      return false
   end

   if (body.destroy ~= nil) then --TODO: на самом деле, можно убрать отсюда init/destroy, после того, как в drivers будут маски
      if (type(body.destroy) ~= "function") then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not start (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy not function'})
         return false
      end
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not start (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init not function'})
         return false
      end

      local init_status, init_returned_data = pcall(body.init)

      if (init_status ~= true) then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not start (init function error: '..(init_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(init_returned_data or "")})
         return false
      end
   end

   bus_events_main_scripts_table[uuid] = nil
   bus_events_main_scripts_table[uuid] = {}
   bus_events_main_scripts_table[uuid].body = body
   bus_events_main_scripts_table[uuid].mask = script_params.object

   log_bus_events_info('Bus-event "'..script_params.name..'" active on mask "'..(script_params.object or "")..'"', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active on mask "'..(script_params.object or "")..'"'})

   return true
end

function bus_events_private.unload(uuid)
   local script_params = scripts.get({uuid = uuid})

   if (bus_events_main_scripts_table[uuid] == nil) then
      log_bus_events_error('Attempt to stop bus-event script "'..script_params.name..'": no loaded', script_params.uuid)
      return false
   end

   local body = bus_events_main_scripts_table[uuid].body

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_bus_events_error('Attempt to stop non-bus-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_bus_events_error('Bus-event script "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not stop (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init not function'})
         return false
      end
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not stop (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy not function'})
         return false
      end

      local destroy_status, destroy_returned_data = pcall(body.destroy)
      if (destroy_status ~= true) then
         log_bus_events_error('Bus-event script "'..script_params.name..'" not stop (destroy function error: '..(destroy_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(destroy_returned_data or "")})
         return false
      end
      if (destroy_returned_data == false) then
         log_bus_events_warning('Bus-event script "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
         return false
      end
   end

   log_bus_events_info('Bus-event script "'..script_params.name..'" set status to non-active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Not active'})
   bus_events_main_scripts_table[uuid] = nil
   return true
end

function bus_events_private.run_once(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_bus_events_error('Attempt to run non-busevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not run (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Run: not found'})
      return false
   end

   if (script_params.body == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not run (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Run: no body'})
      return false
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_bus_events_error('Web-event "'..script_params.name..'" not run (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Run: body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Bus event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, err_msg = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_bus_events_error('Bus-event "'..script_params.name..'" not run (load error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Run: pcall error: '..(err_msg or "")})
      return false
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_bus_events_error('Bus-event "'..script_params.name..'" not run ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Run: "event_handler" function not found or no function'})
      return false
   end

   log_bus_events_info('Bus-event "'..script_params.name..'" runned once', script_params.uuid)
   local value = 0
   local topic = "once"
   local pcall_status, returned_data = pcall(body.event_handler, value, topic)
   if (pcall_status ~= true) then
      returned_data = tostring(returned_data)
      log_bus_events_error('Bus-event "'..script_params.name..'" generate error: '..(returned_data or ""), script_params.uuid)
      scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Event: error: '..(returned_data or "")})
   end

   return true
end


function bus_events_private.reload(uuid)
   local data = scripts.get({uuid = uuid})
   if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
      local result = bus_events_private.unload(uuid)
      if (result == true) then
         return bus_events_private.load(uuid, false)
      else
         return false
      end
   else
      return bus_events_private.load(uuid, false)
   end
end

------------------↓ HTTP API functions ↓------------------

function bus_events_private.http_api_get_list(params, req)
   local tag
   if (params["tag"] ~= nil) then tag = digest.base64_decode(params["tag"]) end
   local table = scripts.get_list(scripts.type.BUS_EVENT, tag)
   return req:render{ json = table }
end

function bus_events_private.http_api_get_tags(params, req)
   local table = scripts.get_tags()
   return req:render{ json = table }
end

function bus_events_private.http_api_create(params, req)
   local data = {}
   if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
   if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
   if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
   if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
   local status, table, err_msg = scripts.create(data.name, scripts.type.BUS_EVENT, data.object, data.tag, data.comment, bus_events_private.init_body)
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function bus_events_private.http_api_copy(params, req)
   local status, table, err_msg = scripts.copy(digest.base64_decode(params["name"]), params["uuid"])
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function bus_events_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local script_table = scripts.get({uuid = params["uuid"]})
      if (script_table ~= nil) then
         if (script_table.status ~= scripts.statuses.STOPPED) then
            script_table.unload_result = bus_events_private.unload(params["uuid"])
            if (script_table.unload_result == true) then
               script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            else
               log_bus_events_warning('Bus-event script "'..script_table.name..'" not deleted(not stopped), need restart glue', script_table.uuid)
               scripts.update({uuid = script_table.uuid, status = scripts.statuses.WARNING, status_msg = 'Not deleted(not stopped), need restart glue'})
            end
            return req:render{ json = script_table }
         else
            script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            return req:render{ json = script_table }
         end
      else
         return req:render{ json = {result = false, error_msg = "Bus-events API delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API delete: no UUID"} }
   end
end

function bus_events_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Bus-events API get: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API get: no UUID"} }
   end
end

function bus_events_private.http_api_reload(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local result = bus_events_private.reload(params["uuid"])
         return req:render{ json = {result = result} }
      else
         return req:render{ json = {result = false, error_msg = "Bus-events API reload: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API reload: No valid UUID"} }
   end
end

function bus_events_private.http_api_run_once(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      bus_events_private.run_once(params["uuid"])
      return req:render{ json = {result = true} }
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API run once: No valid UUID"} }
   end
end

function bus_events_private.http_api_update(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local data = {}
         data.uuid = params["uuid"]
         data.active_flag = params["active_flag"]
         data.object = params["object"]
         if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
         if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
         if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
         if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
         local table = scripts.update(data)
         table.reload_result = bus_events_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Bus-events API update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API update: no UUID"} }
   end
end

function bus_events_private.http_api_update_body(params, req)
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
      if (scripts.get({uuid = uuid}) ~= nil) then
         local table = scripts.update(data)
         if (params["reload"] ~= "none") then
            table.reload_result = bus_events_private.reload(uuid)
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Bus-events API body update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Bus-events API body update: no UUID or no body"} }
   end
end

function bus_events_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      return_object = bus_events_private.http_api_reload(params, req)
   elseif (params["action"] == "get_list") then
      return_object = bus_events_private.http_api_get_list(params, req)
   elseif (params["action"] == "get_tags") then
      return_object = bus_events_private.http_api_get_tags(params, req)
   elseif (params["action"] == "update") then
      return_object = bus_events_private.http_api_update(params, req)
   elseif (params["action"] == "update_body") then
      return_object = bus_events_private.http_api_update_body(params, req)
   elseif (params["action"] == "run_once") then
      return_object = bus_events_private.http_api_run_once(params, req)
   elseif (params["action"] == "create") then
      return_object = bus_events_private.http_api_create(params, req)
   elseif (params["action"] == "copy") then
      return_object = bus_events_private.http_api_copy(params, req)
   elseif (params["action"] == "delete") then
      return_object = bus_events_private.http_api_delete(params, req)
   elseif (params["action"] == "get") then
      return_object = bus_events_private.http_api_get(params, req)
   else
      return_object = req:render{ json = {result = false, error_msg = "Bus-events API: no valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Bus-events API: unknown error(435)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------

function bus_events.process(topic, value, source_uuid, timestamp)
   for uuid, current_script_table in pairs(bus_events_main_scripts_table) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
         script_params.active_flag == scripts.flag.ACTIVE and
         script_params.uuid ~= (source_uuid or "0")) then
         local mask = "^"..current_script_table.mask.."$"
         if (string.find(topic, mask) ~= nil) then
            local status, err_msg, worktime = system.pcall_timecalc(current_script_table.body.event_handler, value, topic, timestamp)
            scripts.update_worktime(uuid, worktime)
            if (status ~= true) then
               err_msg = tostring(err_msg) or ""
               log_bus_events_error('Bus-event "'..script_params.name..'" generate error: '..err_msg, script_params.uuid)
               scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Event: error: '..err_msg})
            end
         end
         fiber.yield()
      end
      fiber.yield()
   end
end

function bus_events.init()
   bus_events.start_all()
   http_system.endpoint_config("/busevents", bus_events_private.http_api)
end

function bus_events.start_all()
   local list = scripts.get_all({type = scripts.type.BUS_EVENT})

   for _, bus_event in pairs(list) do
      bus_events_private.load(bus_event.uuid)
      fiber.yield()
   end
end

return bus_events
