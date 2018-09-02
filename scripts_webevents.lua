#!/usr/bin/env tarantool
local webevents = {}
local webevents_private = {}

local box = box
local http_system = require 'http_system'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_script_system = require 'http_script_system'
local fiber = require 'fiber'

local webevents_script_bodies = {}
webevents.bodies = webevents_script_bodies

------------------ Private functions ------------------

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

   local attach_result = http_script_system.attach_path(script_params.object, callback)

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

------------------ HTTP API functions ------------------

function webevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         local data = scripts.get({uuid = params["uuid"]})
         if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
            local result = webevents_private.unload(params["uuid"])
            if (result == true) then
               webevents_private.load(params["uuid"])
            end
         else
            webevents_private.load(params["uuid"])
         end
         return_object = req:render{ json = {result = true} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Webevents API: No valid UUID"} }
      end
   else
      return_object = req:render{ json = {result = false, error_msg = "Webevents API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Webevents API: Unknown error(335)"} }
   return system.add_headers(return_object)
end

------------------ Public functions ------------------

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
