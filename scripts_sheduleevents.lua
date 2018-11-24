#!/usr/bin/env tarantool
local shedule_events = {}
local shedule_events_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'
local digest = require 'digest'
local cron = require 'cron'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local shedule_event_script_bodies = {}

shedule_events_private.init_body = [[-- The generated script is filled with the default content --
function event_handler()

end]]

local function log_shedule_events_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Shedule-event subsystem", msg, uuid, "")
end

local function log_shedule_events_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Shedule-event subsystem", msg, uuid, "")
end

local function log_shedule_events_info(msg, uuid)
   logger.add_entry(logger.INFO, "Shedule-event subsystem", msg, uuid, "")
end

shedule_events_private.calc_counters_period = 60

------------------↓ Private functions ↓------------------

function shedule_events_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.SHEDULE_EVENT) then
      log_shedule_events_error('Attempt to start non-shedule-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: not found'})
      return false
   end

   if (script_params.body == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: no body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      --log_shedule_events_info('Shedule-event script "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Shedule-event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, returned_data = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (load error: '..(returned_data or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(returned_data or "")})
      return false
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy not function'})
         return false
      end
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init not function'})
         return false
      end

      local init_status, init_returned_data = pcall(body.init)

      if (init_status ~= true) then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (init function error: '..(init_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(init_returned_data or "")})
         return false
      end
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_shedule_events_error('Shedule-event "'..script_params.name..'" not start ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: "event_handler" function not found or no function'})
      return false
   end

   if (script_params.object == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (shedule not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: shedule not found'})
      return false
   end

   local shedule_parsed_result, shedule_parsed_msg = cron.parse(script_params.object)
   if (type(script_params.object) ~= "string" or shedule_parsed_result == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (shedule "'..(script_params.object or "")..'" parsed error: '..shedule_parsed_msg..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: shedule "'..(script_params.object or "")..'" parsed error: '..shedule_parsed_msg})
      return false
   end

   shedule_event_script_bodies[uuid] = nil
   shedule_event_script_bodies[uuid] = {}
   shedule_event_script_bodies[uuid].body = body
   shedule_event_script_bodies[uuid].shedule = script_params.object
   shedule_events_private.recalc_counts(script_params.uuid)

   log_shedule_events_info('Shedule-event script "'..script_params.name..'" active on shedule "'..script_params.object..'"', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active'})
end


function shedule_events_private.unload(uuid)
   local script_params = scripts.get({uuid = uuid})

   if (shedule_event_script_bodies[uuid] == nil) then
      log_shedule_events_error('Attempt to stop bus-event script "'..script_params.name..'": no loaded', script_params.uuid)
      return false
   end

   local body = shedule_event_script_bodies[uuid].body

   if (script_params.type ~= scripts.type.SHEDULE_EVENT) then
      log_shedule_events_error('Attempt to stop non-shedule-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not stop (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init not function'})
         return false
      end
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not stop (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy not function'})
         return false
      end
      local destroy_status, destroy_returned_data = pcall(body.destroy)
      if (destroy_status ~= true) then
         log_shedule_events_error('Shedule-event script "'..script_params.name..'" not stop (destroy function error: '..(destroy_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(destroy_returned_data or "")})
         return false
      end
      if (destroy_returned_data == false) then
         log_shedule_events_warning('Shedule-event script "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
         return false
      end
   end

   log_shedule_events_info('Shedule-event script "'..script_params.name..'" set status to non-active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Not active'})
   shedule_event_script_bodies[uuid] = nil
   return true
end

function shedule_events_private.reload(uuid)
   local data = scripts.get({uuid = uuid})
   if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
      local result = shedule_events_private.unload(uuid)
      if (result == true) then
         return shedule_events_private.load(uuid, false)
      else
         return false
      end
   else
      return shedule_events_private.load(uuid, false)
   end
end


function shedule_events_private.recalc_counts(uuid)
   local script_params = scripts.get({uuid = uuid})
   local scripts_table = shedule_event_script_bodies[uuid]
   if (script_params.status == scripts.statuses.NORMAL and
         script_params.active_flag == scripts.flag.ACTIVE) then
      if (type(scripts_table.shedule) == "string") then
         local expr = cron.parse(scripts_table.shedule)
         if (expr ~= nil) then
            scripts_table.next_time = cron.next(expr) + 1
         else
            log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (shedule "'..(scripts_table.shedule or "")..'" parsed error)', script_params.uuid)
            scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: shedule "'..(scripts_table.shedule or "")..'" parsed error'})
         end
      end
   end
end

function shedule_events_private.time_test()
   for uuid, scripts_table in pairs(shedule_event_script_bodies) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
          script_params.active_flag == scripts.flag.ACTIVE and
          type(scripts_table.next_time) == "number") then
         if (scripts_table.next_time - os.time() <= 1) then
            if (type(scripts_table.body.event_handler) == "function") then
               local status, returned_data, time = system.pcall_timecalc(scripts_table.body.event_handler)
               scripts.update_worktime(uuid, time)
               if (status ~= true) then
                  returned_data = tostring(returned_data)
                  log_shedule_events_error('Shedule-event script event "'..script_params.name..'" generate error: '..(returned_data or ""), script_params.uuid)
                  scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Shedule-event script error: '..(returned_data or "")})
               end
            end
            shedule_events_private.recalc_counts(script_params.uuid)
         end
      end
      fiber.yield()
   end
end

function shedule_events_private.worker()
   while true do
      shedule_events_private.time_test()
      fiber.sleep(1)
   end
end

------------------↓ HTTP API functions ↓------------------

function shedule_events_private.http_api_get_list(params, req)
   local tag
   if (params["tag"] ~= nil) then tag = digest.base64_decode(params["tag"]) end
   local table = scripts.get_list(scripts.type.SHEDULE_EVENT, tag)
   return req:render{ json = table }
end

function shedule_events_private.http_api_get_tags(params, req)
   local table = scripts.get_tags()
   return req:render{ json = table }
end

function shedule_events_private.http_api_create(params, req)
   local data = {}
   if (params["name"] ~= nil) then data.name = digest.base64_decode(params["name"]) end
   if (params["object"] ~= nil) then data.object = digest.base64_decode(params["object"]) end
   if (params["comment"] ~= nil) then data.comment = digest.base64_decode(params["comment"]) end
   if (params["tag"] ~= nil) then data.tag = digest.base64_decode(params["tag"]) end
   local status, table, err_msg = scripts.create(data.name, scripts.type.SHEDULE_EVENT, data.object, data.tag, data.comment, shedule_events_private.init_body)
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function shedule_events_private.http_api_copy(params, req)
   local status, table, err_msg = scripts.copy(digest.base64_decode(params["name"]), params["uuid"])
   return req:render{ json = {result = status, script = table, err_msg = err_msg} }
end

function shedule_events_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local script_table = scripts.get({uuid = params["uuid"]})
      if (script_table ~= nil) then
         if (script_table.status ~= scripts.statuses.STOPPED) then
            script_table.unload_result = shedule_events_private.unload(params["uuid"])
            if (script_table.unload_result == true) then
               script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            else
               log_shedule_events_warning('Timer-event script "'..script_table.name..'" not deleted(not stopped), need restart glue', script_table.uuid)
               scripts.update({uuid = script_table.uuid, status = scripts.statuses.WARNING, status_msg = 'Not deleted(not stopped), need restart glue'})
            end
            return req:render{ json = script_table }
         else
            script_table.delete_result = scripts.delete({uuid = params["uuid"]})
            return req:render{ json = script_table }
         end
      else
         return req:render{ json = {result = false, error_msg = "Shedule-events API delete: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Shedule-events API delete: no UUID"} }
   end
end


function shedule_events_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Shedule-events API get: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Shedule-events API get: no UUID"} }
   end
end

function shedule_events_private.http_api_reload(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts.get({uuid = params["uuid"]}) ~= nil) then
         local result = shedule_events_private.reload(params["uuid"])
         return req:render{ json = {result = result} }
      else
         return req:render{ json = {result = false, error_msg = "Shedule-events API reload: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Shedule-events API reload: no valid UUID"} }
   end
end

function shedule_events_private.http_api_update(params, req)
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
         table.reload_result = shedule_events_private.reload(params["uuid"])
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Shedule-events API update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Shedule-events API update: no UUID"} }
   end
end

function shedule_events_private.http_api_update_body(params, req)
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
            table.reload_result = shedule_events_private.reload(params["uuid"])
         end
         return req:render{ json = table }
      else
         return req:render{ json = {result = false, error_msg = "Shedule-events API body update: UUID not found"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "Shedule-events API body update: no UUID or no body"} }
   end
end

function shedule_events_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      return_object = shedule_events_private.http_api_reload(params, req)
   elseif (params["action"] == "get_list") then
      return_object = shedule_events_private.http_api_get_list(params, req)
   elseif (params["action"] == "get_tags") then
      return_object = shedule_events_private.http_api_get_tags(params, req)
   elseif (params["action"] == "update") then
      return_object = shedule_events_private.http_api_update(params, req)
   elseif (params["action"] == "update_body") then
      return_object = shedule_events_private.http_api_update_body(params, req)
   elseif (params["action"] == "create") then
      return_object = shedule_events_private.http_api_create(params, req)
   elseif (params["action"] == "copy") then
      return_object = shedule_events_private.http_api_copy(params, req)
   elseif (params["action"] == "delete") then
      return_object = shedule_events_private.http_api_delete(params, req)
   elseif (params["action"] == "get") then
      return_object = shedule_events_private.http_api_get(params, req)
   else
      return_object = req:render{ json = {result = false, error_msg = "Shedule-events API: no valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Shedule-events API: unknown error(2430)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------


function shedule_events.init()
   shedule_events.start_all()
   fiber.create(shedule_events_private.worker)
   http_system.endpoint_config("/sheduleevents", shedule_events_private.http_api)
end


function shedule_events.start_all()
   local list = scripts.get_all({type = scripts.type.SHEDULE_EVENT})

   for _, shedule_event in pairs(list) do
      shedule_events_private.load(shedule_event.uuid)
      fiber.yield()
   end
end

return shedule_events
