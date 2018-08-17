#!/usr/bin/env tarantool
local busevents = {}
local busevents_private = {}

local box = box
local http_system = require 'http_system'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local fiber = require 'fiber'

local busevents_script_bodies = {}
busevents.scripts = busevents_script_bodies

local function log_busevent_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Bus-events subsystem", msg, uuid, "")
end

local function log_busevent_info(msg, uuid)
   logger.add_entry(logger.INFO, "Bus-events subsystem", msg, uuid, "")
end

------------------ Private functions ------------------


function busevents_private.load(uuid)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_busevent_error('Attempt to start non-busevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_busevent_error('Web-event "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_busevent_error('Web-event "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if (script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) then
      log_busevent_info('Web-event "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'}) -- TODO: не работает без перезагрузки
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_busevent_error('Web-event "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Bus event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, err_msg = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_busevent_error('Bus-event "'..script_params.name..'" not start (load error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(err_msg or "")})
      return false
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_busevent_error('Bus-event "'..script_params.name..'" not start ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: "event_handler" function not found or no function'})
      return false
   end

   if (script_params.object == nil or script_params.object == "") then
      log_busevent_error('Bus-event "'..script_params.name..'" not start (topic not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: topic not found'})
      return false
   end

   busevents_script_bodies[script_params.object] = body
   log_busevent_info('Bus-event "'..script_params.name..'" active on topic '..(body.topic or ""), script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active on topic '..(body.topic or "")})

   return true
end

function busevents_private.remove_body_by_uuid(uuid)
   for topic, body in pairs(busevents_script_bodies) do
      if (uuid == body._script_uuid) then
         busevents_script_bodies[topic] = nil
      end
   end
end

function busevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil or params["uuid"] ~= "") then
         busevents_private.remove_body_by_uuid(params["uuid"])
         busevents_private.load(params["uuid"])
         return_object = req:render{ json = {error = false} }
      else
         return_object = req:render{ json = {error = true, error_msg = "Busevents API: No valid UUID"} }
      end
   else
      return_object = req:render{ json = {error = true, error_msg = "Busevents API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Busevents API: Unknown error(435)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

------------------ Public functions ------------------

function busevents.process(topic, value, source_uuid)
   if (busevents_script_bodies[topic] ~= nil) then
      local body = busevents_script_bodies[topic]
      local script_params = scripts.get({uuid = body._script_uuid})
      if (type(body) == "table" and
          type(body.event_handler) == "function" and
          script_params.status ~= scripts.statuses.ERROR) then

         if (script_params.uuid == (source_uuid or "0")) then
            return
         end
         local status, returned_data = pcall(body.event_handler, value, topic)
         if (status ~= true) then
            returned_data = tostring(returned_data)
            log_busevent_error('Bus-event "'..body._script_name..'" generate error: '..(returned_data or "")..')', body._script_uuid)
            scripts.update({uuid = body._script_uuid, status = scripts.statuses.ERROR, status_msg = 'Event: error: '..(returned_data or "")})
         end
         return returned_data

      end
   end
end

function busevents.init()
   busevents.start_all()
   http_system.endpoint_config("/busevents", busevents_private.http_api)
end

function busevents.start_all()
   local list = scripts.get_all({type = scripts.type.BUS_EVENT})

   for _, busevent in pairs(list) do
      busevents_private.load(busevent.uuid)
   end
end

return busevents
