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

local webevents_script_bodies = {}
webevents.bodies = webevents_script_bodies

------------------ Private functions ------------------


function webevents_private.generate_log_functions(uuid, script_name)
   local name = "Webevent '"..(script_name or "undefined name").."'"

   local function log_error(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.ERROR, name, msg, uuid, trace)
   end

   local function log_info(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.INFO, name, msg, uuid, trace)
   end

   local function log_warning(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.WARNING, name, msg, uuid, trace)
   end

   return log_error, log_warning, log_info
end

local function log_webevent_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Web-events subsystem", msg, uuid, "")
end

local function log_webevent_info(msg, uuid)
   logger.add_entry(logger.INFO, "Web-events subsystem", msg, uuid, "")
end

function webevents_private.load(uuid)
   webevents_script_bodies[uuid] = nil
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.WEB_EVENT) then
      log_webevent_error('Attempt to stop non-webevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end
   if (script_params.body == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_webevent_info('Web-event "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body)

   if (current_func == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
      return false
   end

   webevents_script_bodies[uuid] = setmetatable({}, {__index=_G})
   webevents_script_bodies[uuid].log_error, webevents_script_bodies[uuid].log_warning, webevents_script_bodies[uuid].log_info = webevents_private.generate_log_functions(uuid, script_params.name)
   webevents_script_bodies[uuid]._script_name = script_params.name

   local status, err_msg = pcall(setfenv(current_func, webevents_script_bodies[uuid]))
   if (status ~= true) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (load error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(err_msg or "")})
      return false
   end

   if (webevents_script_bodies[uuid].init == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Init function not found'})
      return false
   end

   if (webevents_script_bodies[uuid].destroy == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy function not found'})
      return false
   end

   status, err_msg = pcall(webevents_script_bodies[uuid].init)

   if (status ~= true) then
      log_webevent_error('Web-event "'..script_params.name..'" not start (init function error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy function error: '..(err_msg or "")})
      return false
   end

   log_webevent_info('Web-event "'..script_params.name..'" started', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Started'})
end

function webevents_private.unload(uuid)
   local script_body = webevents_script_bodies[uuid]
   local script_params = scripts.get({uuid=uuid})

   if (script_params.type ~= scripts.type.WEB_EVENT) then
      log_webevent_error('Attempt to stop non-webevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_body == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (script_body.init == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not stop (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init function not found'})
      return false
   end

   if (script_body.destroy == nil) then
      log_webevent_error('Web-event "'..script_params.name..'" not stop (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function not found'})
      return false
   end

   local status, err_msg = pcall(script_body.destroy)
   if (status ~= true) then
      log_webevent_error('Web-event "'..script_params.name..'" not stop (destroy function error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(err_msg or "")})
      return false
   end

   log_webevent_info('Web-event "'..script_params.name..'" stopped', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Stopped'})
   webevents_script_bodies[uuid] = nil
   return true
end

function webevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "restart" and params["uuid"] ~= nil) then
      local data = scripts.get({uuid = params["uuid"]})
      if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
         local result = webevents_private.unload(params["uuid"])
         if (result == true) then
            webevents_private.load(params["uuid"])
         end
      else
         webevents_private.load(params["uuid"])
      end
      return_object = req:render{ json = {error = false} }
   else
      return_object = req:render{ json = {error = true, error_msg = "Webevents API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Webevents API: Unknown error(335)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
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
   end
end



return webevents
