#!/usr/bin/env tarantool
local webevents = {} -- TODO: переименовать в соотвествии с остальными
local webevents_private = {}

local box = box
local http_system = require 'http_system'

local inspect = require 'libs/inspect'
local digest = require 'digest'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_script_system = require 'http_script_system'
local fiber = require 'fiber'

local webevents_script_bodies = {}
webevents.bodies = webevents_script_bodies

------------------↓ Private functions ↓------------------

local function log_web_events_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Web-events subsystem", msg, uuid, "")
end

local function log_web_events_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Web-events subsystem", msg, uuid, "")
end

local function log_web_events_info(msg, uuid)
   logger.add_entry(logger.INFO, "Web-events subsystem", msg, uuid, "")
end

function webevents_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.WEB_EVENT) then
      log_web_events_error('Attempt to start non-webevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_web_events_error('Web-event "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_web_events_error('Web-event "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_web_events_info('Web-event "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_web_events_error('Web-event "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Webevent '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, returned_data = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_web_events_error('Web-event "'..script_params.name..'" not start (load error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(returned_data or "")})
      return false
   end

   if (body.http_callback == nil or type(body.http_callback) ~= "function") then
      log_web_events_error('Web-event "'..script_params.name..'" not start (http_callback function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: http_callback function not found or no function'})
      return false
   end

   if (script_params.object == nil or script_params.object == "") then
      log_web_events_error('Web-event "'..script_params.name..'" not start (endpoint not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: endpoint not found'})
      return false
   end

   webevents_script_bodies[uuid] = nil
   webevents_script_bodies[uuid] = body

   local callback = http_script_system.generate_callback_func(webevents_script_bodies[uuid].http_callback)

   local attach_result = http_script_system.attach_path(script_params.object, callback, uuid)

   if (attach_result == false) then
      log_web_events_error('Web-event "'..script_params.name..'" not start (duplicate path "'..(script_params.object or '')..'"', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: duplicate path'})
   else
      log_web_events_info('Web-event "'..script_params.name..'" started and attached path "'..(script_params.object or '')..'"', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Started'})
   end

end


function webevents_private.unload(uuid)
   local body = webevents_script_bodies[uuid]
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.WEB_EVENT) then
      log_web_events_error('Attempt to stop non-webevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_web_events_error('Web-event "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   http_script_system.remove_path(script_params.object)

   log_web_events_info('Web-event "'..script_params.name..'" stopped', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Stopped'})
   webevents_script_bodies[uuid] = nil
   return true
end


function webevents_private.reload(uuid)
   local data = scripts.get({uuid = uuid})
   if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
      local result = webevents_private.unload(uuid)
      if (result == true) then
         return webevents_private.load(uuid, false)
      else
         return false
      end
   else
      return webevents_private.load(uuid, false)
   end
end


------------------↓ HTTP API functions ↓------------------

function webevents_private.http_api_get_list(params, req)
   local table = scripts.get_list(scripts.type.WEB_EVENT)
   return req:render{ json = table }
end

function webevents_private.http_api_create(params, req)
   local status, table, err_msg = scripts.create(params["name"], scripts.type.WEB_EVENT, params["object"])
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function webevents_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local script_table = scripts.get({uuid = params["uuid"]})
      if (script_table ~= nil) then
         local table = scripts.update({uuid = params["uuid"], active_flag = scripts.flag.NON_ACTIVE})
         table.unload_result = webevents_private.unload(params["uuid"])
         if (table.unload_result == true) then
            table = scripts.delete({uuid = params["uuid"]})
         else
            log_web_events_warning('Web-event script "'..script_table.name..'" not deleted(not stopped), need restart glue', script_table.uuid)
            scripts.update({uuid = script_table.uuid, status = scripts.statuses.WARNING, status_msg = 'Not deleted(not stopped), need restart glue'})
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Webevents API Delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Webevents API Delete: no UUID"} }
   end
end


function webevents_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Webevents API Get: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Webevents API Get: no UUID"} }
   end
end

function webevents_private.http_api_reload(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local result = webevents_private.reload(params["uuid"])
         return req:render{ json = {result = result} }
      else
         return req:render{ json = {result = false, error_msg = "Webevents API Delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Webevents API: No valid UUID"} }
   end
end

function webevents_private.http_api_update(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local data = {}
         data.uuid = params["uuid"]
         data.active_flag = params["active_flag"]
         if (params["name"] ~= nil) then data.name = string.gsub(params["name"], "+", " ") end
         if (params["object"] ~= nil) then data.object = string.gsub(params["object"], "+", " ") end
         local table = scripts.update(data)
         table.reload_result = webevents_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Busevents API Update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Busevents API Update: no UUID"} }
   end
end

function webevents_private.http_api_update_body(params, req)
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
         table.reload_result = webevents_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Busevents API body update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Busevents API body update: no UUID or no body"} }
   end
end

function webevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      return_object = webevents_private.http_api_reload(params, req)
   elseif (params["action"] == "get_list") then
      return_object = webevents_private.http_api_get_list(params, req)
   elseif (params["action"] == "update") then
      return_object = webevents_private.http_api_update(params, req)
   elseif (params["action"] == "update_body") then
      return_object = webevents_private.http_api_update_body(params, req)
   elseif (params["action"] == "create") then
      return_object = webevents_private.http_api_create(params, req)
   elseif (params["action"] == "delete") then
      return_object = webevents_private.http_api_delete(params, req)
   elseif (params["action"] == "get") then
      return_object = webevents_private.http_api_get(params, req)
   else
      return_object = req:render{ json = {result = false, error_msg = "Webevents API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Webevents API: Unknown error(335)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------

function webevents.init()
   webevents.start_all()
   http_system.endpoint_config("/webevents", webevents_private.http_api)
end

function webevents.start_all()
   local list = scripts.get_all({type = scripts.type.WEB_EVENT})

   for _, webevent in pairs(list) do
      webevents_private.load(webevent.uuid)
      fiber.yield()
   end
end

return webevents
