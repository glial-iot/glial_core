#!/usr/bin/env tarantool
local settings = {}
local settings_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box
local clock = require 'clock'

local system = require 'system'
local config = require 'config'


------------------↓ Private functions ↓------------------

------------------↓ HTTP API functions ↓------------------
function settings_private.http_api_get(params, req)
   local status, param, value, description
   if (params["param"] ~= nil) then
      status, param, value, description = settings.get(params["param"])
      if (status == true) then
         return req:render{ json = {param = param, value = value, description = description} }
      else
         return req:render{ json = {result = false, error_msg = "No found param"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "No param param"} }
   end
end

function settings_private.http_api_set_param(params, req)
   if (params["param"] ~= nil and params["value"] ~= nil) then
      settings.set(params["param"], params["value"], params["description"])
      return req:render{ result = true }
   end

   return req:render{ result = false, error_msg = "No param param or value" }
end

function settings_private.http_api(req)
   local return_object
   local params = req:param()
   if (params["action"] == "set") then
      return_object = settings_private.http_api_set_param(params, req)

   elseif (params["action"] == "get") then
      return_object = settings_private.http_api_get(params, req)

   else
      return_object = req:render{ json = {result = false, error_msg = "Settings API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Settings API: Unknown error(624)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------


function settings.get(param, default_value)

   if (param == nil) then return false end
   local tuple = settings.settings_storage.index.param:get(param)

   if (tuple ~= nil) then
      return true, tuple["value"], tuple["param"], tuple["description"]
   else
      if (default_value ~= nil) then
         return true, default_value
      else
         return false
      end
   end
end

function settings.set(param, value, description)
   if (param == nil or value == nil) then return end
   if (description == nil) then
      settings.settings_storage:upsert({param, value, ""}, {{"=", 2, value}})
   else
      settings.settings_storage:upsert({param, value, description}, {{"=", 2, value} , {"=", 3, description}})
   end
end



function settings.storage_init()
   local format = {
      {name='param',       type='string'},   --1
      {name='value',       type='string'},   --2
      {name='description', type='string'},   --3
   }
   settings.settings_storage = box.schema.space.create('settings', {if_not_exists = true, format = format, id = config.id.settings})
   settings.settings_storage:create_index('param', {parts = {'param'}, if_not_exists = true})
end

function settings.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/settings", settings_private.http_api)
end

function settings.init()
   settings.storage_init()
   settings.http_init()
end

return settings
