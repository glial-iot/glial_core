#!/usr/bin/env tarantool

local export = {}
local box = box

local logger = require 'logger'

local impact = require 'exports/impact'
local influx = require 'exports/influx'

function export.init()
   impact.init()
   influx.init()

   local http_system = require 'http_system'
   http_system.endpoint_config("/export", export.http_api_handler)
end


function export.send_value(topic, value)
   impact.send_value(topic, value)
   influx.send_value(topic, value)
end

function export.http_api_handler(req)
   local params = req:param()
   local return_object

   if (params["action"] == "set") then
      if (params["type"] == "influx") then
         if (params["value"] == "true" or params["value"] == "false") then
            influx.set_status(params["value"])
         else
            return_object = req:render{ json = {error = true, error_msg = "Export API set: No valid value"} }
         end

      elseif (params["type"] == "impact") then
         if (params["value"] == "true" or params["value"] == "false") then
            impact.set_status(params["value"])
         else
            return_object = req:render{ json = {error = true, error_msg = "Export API set: No valid value"} }
         end

      else
         return_object = req:render{ json = {error = true, error_msg = "Export API set: No valid type"} }
      end

   elseif (params["action"] == "get") then
      if (params["type"] == "influx") then
         local value = influx.get_status()
         return_object = req:render{ json = {error = false, value = value} }
      elseif (params["type"] == "impact") then
         local value = impact.get_status()
         return_object = req:render{ json = {error = false, value = value} }
      else
         return_object = req:render{ json = {error = true, error_msg = "Export API set: No valid type"} }
      end


   else
      return_object = req:render{ json = {error = true, error_msg = "Exports API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Exports API: Unknown error(214)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end


return export

