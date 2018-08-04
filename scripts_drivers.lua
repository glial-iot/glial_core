#!/usr/bin/env tarantool
local drivers = {}
local drivers_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local drivers_script_bodies = {}

local function log_driver_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Drivers subsystem", msg, uuid, "")
end

local function log_driver_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Drivers subsystem", msg, uuid, "")
end

local function log_driver_info(msg, uuid)
   logger.add_entry(logger.INFO, "Drivers subsystem", msg, uuid, "")
end

------------------ Private functions ------------------

function drivers_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.DRIVER) then
      log_driver_error('Attempt to start non-driver script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_driver_error('Driver "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_driver_error('Driver "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_driver_info('Driver "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_driver_error('Driver "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
      return false
   end

   local bus = require('bus')
   local log_script_name = "Driver '"..(script_params.name or "undefined name").."'"
   body = setmetatable({}, {__index=_G})
   body.log_error, body.log_warning, body.log_info, body.log_user = logger.generate_log_functions(uuid, log_script_name)
   body.log, body.print = body.log_user, body.log_user
   body._script_name = script_params.name
   body._script_uuid = script_params.uuid
   body.update_value, body.shadow_update_value, body.get_value, body.bus_serialize  = bus.update_value, bus.shadow_update_value, bus.get_value, bus.serialize
   body.fiber = {}
   body.fiber.create = scripts.generate_fibercreate(uuid, log_script_name)
   body.fiber.sleep, body.fiber.kill, body.fiber.yield, body.fiber.self, body.fiber.status = fiber.sleep, fiber.kill, fiber.yield, fiber.self, fiber.status
   scripts.store[script_params.uuid] = scripts.store[script_params.uuid] or {}
   body.store = scripts.store[script_params.uuid]

   local status, returned_data = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_driver_error('Driver "'..script_params.name..'" not start (load error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(returned_data or "")})
      return false
   end

   if (body.init == nil or type(body.init) ~= "function") then
      log_driver_error('Driver "'..script_params.name..'" not start (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Init function not found or no function'})
      return false
   end

   if (body.destroy == nil or type(body.init) ~= "function") then
      log_driver_error('Driver "'..script_params.name..'" not start (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy function not found or no function'})
      return false
   end

   status, returned_data = pcall(body.init)

   if (status ~= true) then
      log_driver_error('Driver "'..script_params.name..'" not start (init function error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(returned_data or "")})
      return false
   end

   drivers_script_bodies[uuid] = nil
   drivers_script_bodies[uuid] = body
   log_driver_info('Driver "'..script_params.name..'" started', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Started'})
end

function drivers_private.unload(uuid)
   local body = drivers_script_bodies[uuid]
   local script_params = scripts.get({uuid=uuid})

   if (script_params.type ~= scripts.type.DRIVER) then
      log_driver_error('Attempt to stop non-driver script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_driver_error('Driver "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init == nil or type(body.init) ~= "function") then
      log_driver_error('Driver "'..script_params.name..'" not stop (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init function not found or no function'})
      return false
   end

   if (body.destroy == nil or type(body.init) ~= "function") then
      log_driver_error('Driver "'..script_params.name..'" not stop (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function not found or no function'})
      return false
   end

   local status, returned_data = pcall(body.destroy) --если возвращает false, то невозможно завершить без перезагрузки, warning
    if (status ~= true) then
      log_driver_error('Driver "'..script_params.name..'" not stop (destroy function error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(returned_data or "")})
      return false
   end

   if (returned_data == false) then
      log_driver_warning('Driver "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
      return false
   end

   log_driver_info('Driver "'..script_params.name..'" stopped', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Stopped'})
   drivers_script_bodies[uuid] = nil
   return true
end

------------------ HTTP API functions ------------------

function drivers_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         local data = scripts.get({uuid = params["uuid"]})
         if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
            local result = drivers_private.unload(params["uuid"])
            if (result == true) then
               drivers_private.load(params["uuid"])
            end
         else
            drivers_private.load(params["uuid"])
         end
         return_object = req:render{ json = {error = false} }
      else
         return_object = req:render{ json = {error = true, error_msg = "Drivers API: No valid UUID"} }
      end
   --elseif (params["action"] == "create") then

   else
      return_object = req:render{ json = {error = true, error_msg = "Drivers API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Drivers API: Unknown error(233)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end




------------------ Public functions ------------------

function drivers.init()
   drivers.start_all()
   http_system.endpoint_config("/drivers", drivers_private.http_api)
end

function drivers.start_all()
   local list = scripts.get_all({type = scripts.type.DRIVER})

   for _, driver in pairs(list) do
      drivers_private.load(driver.uuid)
   end
end

return drivers
