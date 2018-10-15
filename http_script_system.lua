#!/usr/bin/env tarantool
local http_script_system = {}
local http_script_system_private = {}

local box = box
local log = require 'log'
local inspect = require 'libs/inspect'

local logger = require 'logger'
local http_system = require 'http_system'
local system = require 'system'
local config = require 'config'

http_script_system_private.path_table = {}
http_script_system_private.main_path = "/we/:name"

------------------↓ Private functions ↓------------------ --перенести все это в webevents

function http_script_system_private.main_handler(req)
   local name = req:stash('name')
   local return_object
   if (http_script_system_private.path_table[name] ~= nil) then
      local status, returned_data = pcall(http_script_system_private.path_table[name].handler, req)
      if (status == true) then
         return_object = returned_data
      else
         logger.add_entry(logger.ERROR, "Web-events subsystem", returned_data, http_script_system_private.path_table[name].uuid, "")
         return_object = req:render{ json = {result = false, msg = returned_data } }
      end

   else
      local avilable_endpoints = {}
      for endpoint, _ in pairs(http_script_system_private.path_table) do
         table.insert(avilable_endpoints, endpoint)
      end

      return_object = req:render{ json = {result = false, msg = "Endpoint '"..name.."' not found",  avilable_endpoints = avilable_endpoints} }
   end

   return system.add_headers(return_object)
end

function http_script_system.endpoint_config(path, handler)
   http_script_system.server:route({ path = path }, handler)
end


-------------------Public functions-------------------

function http_script_system.generate_callback_func(handler)
   return function(req)
      local params = req:param()
      local return_object

      local json_result, raw_result = handler(params, req)
      if (json_result ~= nil) then
         return_object = req:render{ json = json_result }
      else
         if (raw_result ~= nil) then
            return_object = raw_result
         else
            return_object = req:render{ json = {} }
         end
      end

      return system.add_headers(return_object)
   end
end

function http_script_system.attach_path(path, handler, uuid)
   if (http_script_system_private.path_table[path] ~= nil) then
      return false
   else
      http_script_system_private.path_table[path] = {}
      http_script_system_private.path_table[path].handler = handler
      http_script_system_private.path_table[path].uuid = uuid
      return true
   end

end

function http_script_system.remove_path(path)
   http_script_system_private.path_table[path] = nil
end

function http_script_system.init()
   http_system.endpoint_config(http_script_system_private.main_path, http_script_system_private.main_handler)
end

return http_script_system
