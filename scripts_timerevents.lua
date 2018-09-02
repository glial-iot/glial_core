#!/usr/bin/env tarantool
local timerevents = {}
local timerevents_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local timer_event_script_bodies = {}

local function log_timer_events_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Timer-event subsystem", msg, uuid, "")
end

local function log_timer_events_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Timer-event subsystem", msg, uuid, "")
end

local function log_timer_events_info(msg, uuid)
   logger.add_entry(logger.INFO, "Timer-event subsystem", msg, uuid, "")
end

------------------ Private functions ------------------

function timerevents_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.TIMER_EVENT) then
      log_timer_events_error('Attempt to start non-timer-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_timer_events_info('Timer-event script "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_timer_events_error('Timer-event script "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
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
   timer_event_script_bodies[uuid].counter = sec_counter
   timer_event_script_bodies[uuid].period = sec_counter
   log_timer_events_info('Timer-event script "'..script_params.name..'" active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active'})
end

function timerevents_private.unload(uuid)
   local body = timer_event_script_bodies[uuid]
   local script_params = scripts.get({uuid = uuid})

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
         log_timer_events_warning('Timer-event script "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
         return false
      end
   end

   log_timer_events_info('Timer-event script "'..script_params.name..'" set status to non-active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Not active'})
   timer_event_script_bodies[uuid] = nil
   return true
end


function timerevents_private.process()
   for uuid, scripts_table in pairs(timer_event_script_bodies) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
          script_params.active_flag == scripts.flag.ACTIVE and
          type(scripts_table.counter) == "number") then
         if (scripts_table.counter <= 1) then
            if (type(scripts_table.body.event_handler) == "function") then
               local status, returned_data = pcall(scripts_table.body.event_handler)
               if (status ~= true) then
                  returned_data = tostring(returned_data)
                  log_timer_events_error('Timer-event script event "'..script_params.name..'" generate error: '..(returned_data or "")..')', script_params.uuid)
                  scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Shedule-event script error: '..(returned_data or "")})
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

function timerevents_private.worker()
   while true do
      timerevents_private.process()
      fiber.sleep(1)
   end
end

------------------ HTTP API functions ------------------

function timerevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         local data = scripts.get({uuid = params["uuid"]})
         if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
            local result = timerevents_private.unload(params["uuid"])
            if (result == true) then
               timerevents_private.load(params["uuid"])
            end
         else
            timerevents_private.load(params["uuid"])
         end
         return_object = req:render{ json = {result = true} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Timer event API: No valid UUID"} }
      end

   else
      return_object = req:render{ json = {result = false, error_msg = "Timer event API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Timer event API: Unknown error(2433)"} }
   return system.add_headers(return_object)
end

------------------ Public functions ------------------


function timerevents.init()
   timerevents.start_all()
   fiber.create(timerevents_private.worker)
   http_system.endpoint_config("/timerevents", timerevents_private.http_api)
end




function timerevents.start_all()
   local list = scripts.get_all({type = scripts.type.TIMER_EVENT})

   for _, timerevent in pairs(list) do
      timerevents_private.load(timerevent.uuid)
      fiber.yield()
   end
end

return timerevents
