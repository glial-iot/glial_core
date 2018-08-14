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

------------------ Private functions ------------------


function http_script_system_private.main_handler(req)
   local name = req:stash('name')
   if (http_script_system_private.path_table[name] ~= nil) then
      local status, returned_data = pcall(http_script_system_private.path_table[name], req)
      if (status == true) then
         return returned_data
      else
         return req:render{ json = {error = true, msg = returned_data } }
      end
       --обернуть в xpcall и генерировать записи в логе с uuid
   end

   return req:render{ json = {avilable_endpoints = http_script_system_private.path_table} }
end

function http_script_system.init_client()
   http_script_system.client = require('http.client')
end

function http_script_system.endpoint_config(path, handler)
   http_script_system.server:route({ path = path }, handler)
end


-------------------Public functions-------------------

function http_script_system.generate_callback_func(handler)
   return function(req)
      local params = req:param()
      local ret

      local result = handler(params, req)
      if (result ~= nil) then
         ret = req:render{ json = result }
      else
         ret = req:render{ json = {} }
      end

      ret.headers = ret.headers or {}
      ret.headers['Access-Control-Allow-Origin'] = '*';
      return ret
   end
end



function http_script_system.attach_path(path, handler)
   if (http_script_system_private.path_table[path] ~= nil) then
      return false, "duplicate"
   else
      http_script_system_private.path_table[path] = handler
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
