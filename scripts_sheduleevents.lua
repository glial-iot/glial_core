#!/usr/bin/env tarantool
local shedule_events = {}
local shedule_events_private = {}

local box = box

local fiber = require 'fiber'
local inspect = require 'libs/inspect'
local cron = require('cron')

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local http_system = require 'http_system'

local shedule_event_script_bodies = {}

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

------------------ Private functions ------------------

function shedule_events_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.SHEDULE_EVENT) then
      log_shedule_events_error('Attempt to start non-shedule-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_shedule_events_info('Shedule-event script "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'})
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
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

   shedule_event_script_bodies[uuid] = nil
   shedule_event_script_bodies[uuid] = {}
   shedule_event_script_bodies[uuid].body = body
   shedule_event_script_bodies[uuid].shedule = script_params.object
   shedule_events_private.recalc_counts(script_params.uuid)
   log_shedule_events_info('Shedule-event script "'..script_params.name..'" active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active'})
end

function shedule_events_private.unload(uuid)
   local body = shedule_event_script_bodies[uuid]
   local script_params = scripts.get({uuid = uuid})

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


function shedule_events_private.recalc_counts(uuid)
   local script_params = scripts.get({uuid = uuid})
   local scripts_table = shedule_event_script_bodies[uuid]
   if (script_params.status == scripts.statuses.NORMAL and
         script_params.active_flag == scripts.flag.ACTIVE) then
      if (type(scripts_table.shedule) == "string") then
         local expr = cron.parse(scripts_table.shedule)
         --print("recalc_counts", scripts_table.shedule, cron.next(expr), cron.next(expr)-os.time())
         if (expr ~= nil) then
            scripts_table.next_time = cron.next(expr) + 1
         else
            log_shedule_events_error('Shedule-event script "'..script_params.name..'" not start (error shedule parsed)', script_params.uuid)
            scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: error shedule parsed'})
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
         --print("counts_update", scripts_table.body._script_name, scripts_table.next_time - os.time(), scripts_table.shedule)
         if (scripts_table.next_time - os.time() <= 1) then
            if (type(scripts_table.body.event_handler) == "function") then
               --print("counts_start")
               local status, returned_data = pcall(scripts_table.body.event_handler)
               if (status ~= true) then
                  returned_data = tostring(returned_data)
                  log_shedule_events_error('Shedule-event script event "'..script_params.name..'" generate error: '..(returned_data or "")..')', script_params.uuid)
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

------------------ HTTP API functions ------------------

function shedule_events_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         local data = scripts.get({uuid = params["uuid"]})
         if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
            local result = shedule_events_private.unload(params["uuid"])
            if (result == true) then
               shedule_events_private.load(params["uuid"])
            end
         else
            shedule_events_private.load(params["uuid"])
         end
         return_object = req:render{ json = {result = true} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Shedule event API: No valid UUID"} }
      end

   else
      return_object = req:render{ json = {result = false, error_msg = "Shedule event API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Shedule event API: Unknown error(2430)"} }
   return system.add_headers(return_object)
end

------------------ Public functions ------------------


function shedule_events.init()
   shedule_events.start_all()
   fiber.create(shedule_events_private.worker)
   http_system.endpoint_config("/sheduleevents", shedule_events_private.http_api)
end


function shedule_events.start_all()
   local list = scripts.get_all({type = scripts.type.SHEDULE_EVENT})

   for _, sheduleevent in pairs(list) do
      shedule_events_private.load(sheduleevent.uuid)
      fiber.yield()
   end
end

return shedule_events
