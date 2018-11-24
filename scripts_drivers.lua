#!/usr/bin/env tarantool
local drivers = {}
local drivers_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'
local digest = require 'digest'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local drivers_script_bodies = {}

drivers_private.init_body = [[-- The generated script is filled with the default content --

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

function topic_update_callback(value, topic, timestamp)
   print("Test driver callback:", value, topic)
end]]

local function log_drivers_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Drivers subsystem", msg, uuid, "")
end

local function log_drivers_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Drivers subsystem", msg, uuid, "")
end

local function log_drivers_info(msg, uuid)
   logger.add_entry(logger.INFO, "Drivers subsystem", msg, uuid, "")
end

------------------↓ Private functions ↓------------------

function drivers_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.DRIVER) then
      log_drivers_error('Attempt to start non-driver script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_drivers_error('Driver "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: not found'})
      return false
   end

   if (script_params.body == nil) then
      log_drivers_error('Driver "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: no body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      --log_drivers_info('Driver "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_drivers_error('Driver "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Driver '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, returned_data = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_drivers_error('Driver "'..script_params.name..'" not start (load error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(returned_data or "")})
      return false
   end

   if (body.init == nil or type(body.init) ~= "function") then
      log_drivers_error('Driver "'..script_params.name..'" not start (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function not found or no function'})
      return false
   end

   if (body.destroy == nil or type(body.destroy) ~= "function") then
      log_drivers_error('Driver "'..script_params.name..'" not start (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy function not found or no function'})
      return false
   end

   if (body.masks ~= nil) then
      if (type(body.masks) == "table" and #body.masks > 0) then
         if (type(body.topic_update_callback) == "function") then
            for i, mask in pairs(body.masks) do
               if (type(mask) ~= "string") then
                  log_drivers_error('Driver "'..script_params.name..'" not start (mask '..i..' not string)', script_params.uuid)
                  scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: mask '..i..' not string'})
                  return false
               end
            end
         else
            log_drivers_error('Driver "'..script_params.name..'" not start (topic_update_callback function not found)', script_params.uuid)
            scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: topic_update_callback function not found or no function'})
            return false
         end
      else
         log_drivers_error('Driver "'..script_params.name..'" not start (mask in not a table or blank table)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: mask in not a table or blank table'})
         return false
      end
   end

   status, returned_data = pcall(body.init)

   if (status ~= true) then
      log_drivers_error('Driver "'..script_params.name..'" not start (init function error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(returned_data or "")})
      return false
   end

   drivers_script_bodies[uuid] = nil
   drivers_script_bodies[uuid] = body
   log_drivers_info('Driver "'..script_params.name..'" started', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Started'})
end

function drivers_private.unload(uuid)
   local body = drivers_script_bodies[uuid]
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.DRIVER) then
      log_drivers_error('Attempt to stop non-driver script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_drivers_error('Driver "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init == nil or type(body.init) ~= "function") then
      log_drivers_error('Driver "'..script_params.name..'" not stop (init function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init function not found or no function'})
      return false
   end

   if (body.destroy == nil or type(body.destroy) ~= "function") then
      log_drivers_error('Driver "'..script_params.name..'" not stop (destroy function not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function not found or no function'})
      return false
   end

   local status, returned_data = pcall(body.destroy)
   if (status ~= true) then
      log_drivers_error('Driver "'..script_params.name..'" not stop (destroy function error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(returned_data or "")})
      return false
   end

   if (returned_data == false) then
      log_drivers_warning('Driver "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
      return false
   end

   log_drivers_info('Driver "'..script_params.name..'" stopped', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Stopped'})
   drivers_script_bodies[uuid] = nil
   return true
end


function drivers_private.reload(uuid)
   local data = scripts.get({uuid = uuid})
   if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
      local result = drivers_private.unload(uuid)
      if (result == true) then
         return drivers_private.load(uuid, false)
      else
         return false
      end
   else
      return drivers_private.load(uuid, false)
   end
end

------------------↓ HTTP API functions ↓------------------

function drivers_private.http_api_get_list(params, req)
   local tag
   if (params["tag"] ~= nil) then tag = digest.base64_decode(params["tag"]) end
   local table = scripts.get_list(scripts.type.DRIVER, tag)
   return req:render{ json = table }
end

function drivers_private.http_api_get_tags(params, req)
   local table = scripts.get_tags()
   return req:render{ json = table }
end

function drivers_private.http_api_create(params, req)
   local data = {}
   if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
   if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
   if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
   if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
   local status, table, err_msg = scripts.create(data.name, scripts.type.DRIVER, data.object, data.tag, data.comment, drivers_private.init_body)
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function drivers_private.http_api_copy(params, req)
   local status, table, err_msg = scripts.copy(digest.base64_decode(params["name"]), params["uuid"])
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function drivers_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local script_table = scripts.get({uuid = params["uuid"]})
      if (script_table ~= nil) then
         if (script_table.status == scripts.statuses.STOPPED and script_table.active_flag == scripts.flag.NON_ACTIVE) then
            local result = scripts.delete({uuid = params["uuid"]})
            return req:render{ json = {result = result} }
         end
         local table = scripts.update({uuid = params["uuid"], active_flag = scripts.flag.NON_ACTIVE})
         table.unload_result = drivers_private.unload(params["uuid"])
         if (table.unload_result == true) then
            table.delete_result = scripts.delete({uuid = params["uuid"]})
         else
            log_drivers_warning('Driver "'..script_table.name..'" not deleted(not stopped), maybe, need restart glue', script_table.uuid)
            scripts.update({uuid = script_table.uuid, status = scripts.statuses.WARNING, status_msg = 'Not deleted(not stopped), maybe, need restart glue'})
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Drivers API delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Drivers API delete: no UUID"} }
   end
end


function drivers_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Drivers API get: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Drivers API get: no UUID"} }
   end
end

function drivers_private.http_api_reload(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local result = drivers_private.reload(params["uuid"])
         return req:render{ json = {result = result} }
      else
         return req:render{ json = {result = false, error_msg = "Drivers API reload: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Drivers API reload: no valid UUID"} }
   end
end

function drivers_private.http_api_update(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local data = {}
         data.uuid = params["uuid"]
         data.active_flag = params["active_flag"]
         if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
         if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
         if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
         if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
         local table = scripts.update(data)
         table.reload_result = drivers_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Drivers API update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Drivers API update: no UUID"} }
   end
end

function drivers_private.http_api_update_body(params, req)
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
            table.reload_result = drivers_private.reload(params["uuid"])
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Drivers API body update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Drivers API body update: no UUID or no body"} }
   end
end

function drivers_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      return_object = drivers_private.http_api_reload(params, req)
   elseif (params["action"] == "get_list") then
      return_object = drivers_private.http_api_get_list(params, req)
   elseif (params["action"] == "get_tags") then
      return_object = drivers_private.http_api_get_tags(params, req)
   elseif (params["action"] == "update") then
      return_object = drivers_private.http_api_update(params, req)
   elseif (params["action"] == "update_body") then
      return_object = drivers_private.http_api_update_body(params, req)
   elseif (params["action"] == "create") then
      return_object = drivers_private.http_api_create(params, req)
   elseif (params["action"] == "copy") then
      return_object = drivers_private.http_api_copy(params, req)
   elseif (params["action"] == "delete") then
      return_object = drivers_private.http_api_delete(params, req)
   elseif (params["action"] == "get") then
      return_object = drivers_private.http_api_get(params, req)
   else
      return_object = req:render{ json = {result = false, error_msg = "Drivers API: no valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Drivers API: unknown error(233)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------

function drivers.init()
   drivers.start_all()
   http_system.endpoint_config("/drivers", drivers_private.http_api)
end

function drivers.process(topic, value, source_uuid, timestamp)
   for uuid, script_table in pairs(drivers_script_bodies) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
          script_params.active_flag == scripts.flag.ACTIVE and
          script_params.uuid ~= (source_uuid or "0")) then
         local callback = script_table.topic_update_callback
         local masks = script_table.masks
         if (type(callback) == "function" and type(masks) == "table" and #masks > 0) then
            for _, mask in pairs(masks) do
               mask = "^"..mask.."$"
               if (string.find(topic, mask) ~= nil) then
                  local status, returned_data, time = system.pcall_timecalc(callback, value, topic, timestamp)
                  scripts.update_worktime(uuid, time)
                  if (status ~= true) then
                     returned_data = tostring(returned_data)
                     log_drivers_error('Driver event "'..script_params.name..'" generate error: '..(returned_data or ""), script_params.uuid)
                     scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Driver event error: '..(returned_data or "")})
                  end
                  fiber.yield()
               end
            end
         end
      end
      fiber.yield()
   end
end

function drivers.start_all()
   local list = scripts.get_all({type = scripts.type.DRIVER})

   for _, driver in pairs(list) do
      drivers_private.load(driver.uuid)
      fiber.yield()
   end
end

return drivers
