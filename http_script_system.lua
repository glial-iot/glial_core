#!/usr/bin/env tarantool
local http_script_system = {}
local http_script_system_private = {}

local box = box
local log = require 'log'

local http_system = require 'http_system'
local system = require 'system'
local config = require 'config'

http_script_system_private.path_table = {}
http_script_system_private.main_path = "/we/:name"
http_script_system_private.debug_path = "/we"

------------------ Private functions ------------------

function http_script_system_private.debug_handler(req)
   return req:render{ json = {avilable_endpoints = http_script_system_private.path_table} }
end

function http_script_system_private.main_handler(req)
   local name = req:stash('name')
   if (http_script_system_private.path_table[name] ~= nil) then
      return http_script_system_private.path_table[name](req)
   end

   return { status = 404, headers = { ['content-type'] = 'text/html; charset=utf8' } }
end

function http_script_system.init_client()
   http_script_system.client = require('http.client')
end

function http_script_system.endpoint_config(path, handler)
   http_script_system.server:route({ path = path }, handler)
end


-------------------Public functions-------------------

function http_script_system.generate_add_remove_functions(uuid, name)
   local logger = require 'logger'

   local function add_path(path, handler)
      logger.add_entry(logger.INFO, name, "Attached path '/we/"..(path or "").."'", uuid, "")
      http_script_system_private.path_table[path] = handler
   end

   local function remove_path(path)
      logger.add_entry(logger.INFO, name, "Detached path '/we/"..(path or "").."'", uuid, "")
      http_script_system_private.path_table[path] = nil
   end

   return add_path, remove_path
end


function http_script_system.init()
   http_system.endpoint_config(http_script_system_private.main_path, http_script_system_private.main_handler)
   http_system.endpoint_config(http_script_system_private.debug_path, http_script_system_private.debug_handler)
end



return http_script_system
