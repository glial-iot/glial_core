#!/usr/bin/env tarantool
local settings = {}
local settings_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box
local clock = require 'clock'
local digest = require 'digest'

local system = require 'system'
local config = require 'config'


------------------↓ Private functions ↓------------------

------------------↓ HTTP API functions ↓------------------
function settings_private.http_api_get(params, req)
   local status, name, value, description
   if (params["name"] ~= nil) then
      status, name, value, description = settings.get(params["name"])
      if (status == true) then
         return req:render{ json = {name = name, value = value, description = description} }
      else
         return req:render{ json = {result = false, error_msg = "No found parameter '"..params["name"].."'"} }
      end
   else
      return req:render{ json = {result = false, error_msg = "No name"} }
   end
end

function settings_private.http_api_get_list(params, req)
   local params_list = settings.get_list()
   return req:render{ json = {params_list} }
end

function settings_private.http_api_set_param(params, req)
   if (params["name"] == nil) then
      return req:render{ json = {result = false, error_msg = "No parameter name"} }
   end

   if (params["value"] == nil) then
      return req:render{ json = {result = false, error_msg = "No parameter value"} }
   end

   local description
   local value

   if (params["description"] ~= nil) then
      description = digest.base64_decode(params["description"])
   end

   if (params["value"] ~= nil) then
      value = digest.base64_decode(params["value"])
   end

   local result = settings.set(params["name"], value, description or "")
   return req:render{ json = {result = result} }
end

function settings_private.http_api_delete(params, req)
   if (params["name"] == nil) then
      return req:render{ json = {result = false, error_msg = "No parameter name"} }
   end

   local result = settings.delete(params["name"])
   return req:render{ json = {result = result} }
end

function settings_private.http_api(req)
   local return_object
   local params = req:param()
   if (params["action"] == "set") then
      return_object = settings_private.http_api_set_param(params, req)

   elseif (params["action"] == "get") then
      return_object = settings_private.http_api_get(params, req)

   elseif (params["action"] == "get_list") then
      return_object = settings_private.http_api_get_list(params, req)

   elseif (params["action"] == "delete") then
      return_object = settings_private.http_api_delete(params, req)

   else
      return_object = req:render{ json = {result = false, error_msg = "Settings API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Settings API: Unknown error(624)"} }
   return system.add_headers(return_object)
end

------------------↓ Public functions ↓------------------


function settings.get(name, default_value)
   if (name == nil) then return false end
   local tuple = settings.settings_storage.index.name:get(name)

   if (tuple ~= nil) then
      return true, tuple["value"], tuple["name"], tuple["description"]
   else
      if (default_value ~= nil) then
         return true, default_value
      else
         return false
      end
   end
end

function settings.get_list()
   local settings_table = {}
   for _, tuple in settings.settings_storage.index.name:pairs() do
      local current_settings_table = {
         setting_name = tuple["name"],
         setting_value = tuple["value"],
         setting_description = tuple["description"] or "",
      }
      table.insert(settings_table, current_settings_table)
   end
   return settings_table
end

function settings.set(name, value, description)
   if (name == nil) then return false end
   if (description == nil and value == nil) then return false end

   if (description ~= nil) then
      settings.settings_storage:upsert({name, "", description}, {{"=", 3, description}})
   end

   if (value ~= nil) then
      settings.settings_storage:upsert({name, value, ""}, {{"=", 2, value}})
   end

   return true
end

function settings.delete(name)
   if (name == nil) then return false end
   settings.settings_storage.index.name:delete(name)
   return true
end


function settings.storage_init()
   local format = {
      {name='name',        type='string'},   --1
      {name='value',       type='string'},   --2
      {name='description', type='string'},   --3
   }
   settings.settings_storage = box.schema.space.create('settings', {if_not_exists = true, format = format, id = config.id.settings})
   settings.settings_storage:create_index('name', {parts = {'name'}, if_not_exists = true})
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
