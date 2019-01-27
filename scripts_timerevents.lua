#!/usr/bin/env tarantool
local timer_events = {}
local timer_events_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'
local digest = require 'digest'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local timer_event_script_bodies = {}

timer_events_private.init_body = [[-- The generated script is filled with the default content --
function event_handler()

end]]

local function log_timer_events_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Timer-event subsystem", msg, uuid, "")
end

local function log_timer_events_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Timer-event subsystem", msg, uuid, "")
end

local function log_timer_events_info(msg, uuid)
   logger.add_entry(logger.INFO, "Timer-event subsystem", msg, uuid, "")
end

------------------↓ Private functions ↓------------------

function timer_events_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.TIMER_EVENT) then
      log_timer_events_error('Attempt to start non-timer-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: not found'})
      return false
   end

   if (script_params.body == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: no body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      --log_timer_events_info('Timer-event script "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Timer-event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, returned_data = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (load error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(returned_data or "")})
      return false
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not start (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy not function'})
         return false
      end
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not start (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init not function'})
         return false
      end

      local init_status, init_returned_data = pcall(body.init)

      if (init_status ~= true) then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not start (init function error: '..(init_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(init_returned_data or "")})
         return false
      end
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_timer_events_error('Timer-event "'..script_params.name..'" not start ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: "event_handler" function not found or no function'})
      return false
   end

   local sec_counter = tonumber(script_params.object)

   if (sec_counter == nil or sec_counter < 1) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (period no number or <1)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: period no number or <1'})
      return false
   end

   timer_event_script_bodies[uuid] = nil
   timer_event_script_bodies[uuid] = {}
   timer_event_script_bodies[uuid].body = body
   timer_event_script_bodies[uuid].counter = 0
   timer_event_script_bodies[uuid].period = sec_counter
   log_timer_events_info('Timer-event script "'..script_params.name..'" active on period '..sec_counter.." s", script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active'})
end

function timer_events_private.unload(uuid)
   local script_params = scripts.get({uuid = uuid})

   if (timer_event_script_bodies[uuid] == nil) then
      log_timer_events_error('Attempt to stop bus-event script "'..script_params.name..'": no loaded', script_params.uuid)
      return false
   end

   local body = timer_event_script_bodies[uuid].body

   if (script_params.type ~= scripts.type.TIMER_EVENT) then
      log_timer_events_error('Attempt to stop non-timer-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not stop (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init not function'})
         return false
      end
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not stop (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy not function'})
         return false
      end
      local destroy_status, destroy_returned_data = pcall(body.destroy)
      if (destroy_status ~= true) then
         log_timer_events_error('Timer-event script "'..script_params.name..'" not stop (destroy function error: '..(destroy_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(destroy_returned_data or "")})
         return false
      end
      if (destroy_returned_data == false) then
         log_timer_events_warning('Timer-event script "'..script_params.name..'" not stopped, need restart glial', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glial'})
         return false
      end
   end

   log_timer_events_info('Timer-event script "'..script_params.name..'" set status to non-active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Not active'})
   timer_event_script_bodies[uuid] = nil
   return true
end


function timer_events_private.reload(uuid)
   local data = scripts.get({uuid = uuid})
   if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
      local result = timer_events_private.unload(uuid)
      if (result == true) then
         return timer_events_private.load(uuid, false)
      else
         return false
      end
   else
      return timer_events_private.load(uuid, false)
   end
end


function timer_events_private.process()
   for uuid, scripts_table in pairs(timer_event_script_bodies) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
          script_params.active_flag == scripts.flag.ACTIVE and
          type(scripts_table.counter) == "number") then
         if (scripts_table.counter <= 1) then
            if (type(scripts_table.body.event_handler) == "function") then
               local status, returned_data, time = system.pcall_timecalc(scripts_table.body.event_handler)
               scripts.update_worktime(uuid, time)
               if (status ~= true) then
                  returned_data = tostring(returned_data)
                  log_timer_events_error('Timer-event script event "'..script_params.name..'" generate error: '..(returned_data or ""), script_params.uuid)
                  scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Timer-event script error: '..(returned_data or "")})
               end
            end
            scripts_table.counter = scripts_table.period
         else
            scripts_table.counter = scripts_table.counter - 1
         end
      end
      fiber.yield()
   end
end

function timer_events_private.worker()
   while true do
      timer_events_private.process()
      fiber.sleep(1)
   end
end

------------------↓ HTTP API functions ↓------------------

function timer_events_private.http_api_get_list(params, req)
   local tag
   if (params["tag"] ~= nil) then tag = digest.base64_decode(params["tag"]) end
   local table = scripts.get_list(scripts.type.TIMER_EVENT, tag)
   return req:render{ json = table }
end

function timer_events_private.http_api_get_tags(params, req)
   local table = scripts.get_tags()
   return req:render{ json = table }
end

function timer_events_private.http_api_create(params, req)
   local data = {}
   if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
   if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
   if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
   if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
   local status, table, err_msg = scripts.create(data.name, scripts.type.TIMER_EVENT, data.object, data.tag, data.comment, timer_events_private.init_body)
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function timer_events_private.http_api_copy(params, req)
   local status, table, err_msg = scripts.copy(digest.base64_decode(params["name"]), params["uuid"])
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function timer_events_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local script_table = scripts.get({uuid = params["uuid"]})
      if (script_table ~= nil) then
         if (script_table.status ~= scripts.statuses.STOPPED) then
            script_table.unload_result = timer_events_private.unload(params["uuid"])
            if (script_table.unload_result == true) then
               script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            else
               log_timer_events_warning('Timer-event script "'..script_table.name..'" not deleted(not stopped), need restart glial', script_table.uuid)
               scripts.update({uuid = script_table.uuid, status = scripts.statuses.WARNING, status_msg = 'Not deleted(not stopped), need restart glial'})
            end
            return req:render{ json = script_table }
         else
            script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            return req:render{ json = script_table }
         end
      else
         return req:render{ json = {result = false, error_msg = "Timer-event API delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Timer-event API delete: no UUID"} }
   end
end


function timer_events_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Timer-event API get: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Timer-event API get: no UUID"} }
   end
end

function timer_events_private.http_api_reload(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local result = timer_events_private.reload(params["uuid"])
         return req:render{ json = {result = result} }
      else
         return req:render{ json = {result = false, error_msg = "Timer-event API reload: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Timer-event API reload: no valid UUID"} }
   end
end

function timer_events_private.http_api_update(params, req)
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
         table.reload_result = timer_events_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Timer-event API update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Timer-event API update: no UUID"} }
   end
end

function timer_events_private.http_api_update_body(params, req)
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
            table.reload_result = timer_events_private.reload(params["uuid"])
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Timer-event API body update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Timer-event API body update: no UUID or no body"} }
   end
end

function timer_events_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      return_object = timer_events_private.http_api_reload(params, req)
   elseif (params["action"] == "get_list") then
      return_object = timer_events_private.http_api_get_list(params, req)
   elseif (params["action"] == "get_tags") then
      return_object = timer_events_private.http_api_get_tags(params, req)
   elseif (params["action"] == "update") then
      return_object = timer_events_private.http_api_update(params, req)
   elseif (params["action"] == "update_body") then
      return_object = timer_events_private.http_api_update_body(params, req)
   elseif (params["action"] == "create") then
      return_object = timer_events_private.http_api_create(params, req)
   elseif (params["action"] == "copy") then
      return_object = timer_events_private.http_api_copy(params, req)
   elseif (params["action"] == "delete") then
      return_object = timer_events_private.http_api_delete(params, req)
   elseif (params["action"] == "get") then
      return_object = timer_events_private.http_api_get(params, req)
   else
      return_object = req:render{ json = {result = false, error_msg = "Timer-event API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Timer-event API: unknown error(2433)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------


function timer_events.init()
   timer_events.start_all()
   fiber.create(timer_events_private.worker)
   http_system.endpoint_config("/timerevents", timer_events_private.http_api)
end

function timer_events.start_all()
   local list = scripts.get_all({type = scripts.type.TIMER_EVENT})

   for _, timer_event in pairs(list) do
      timer_events_private.load(timer_event.uuid)
      fiber.yield()
   end
end

return timer_events
