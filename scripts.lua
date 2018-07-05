#!/usr/bin/env tarantool
local scripts = {}
local scripts_private = {}

local box = box
local uuid_lib = require('uuid')
local digest = require 'digest'


local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
scripts.statuses = {ERROR = "ERROR", WARNING = "WARNING", NORMAL = "NORMAL", STOPPED = "STOPPED"}
scripts.flag = {ACTIVE = "ACTIVE", NON_ACTIVE = "NON_ACTIVE"}
scripts.type = {WEB_EVENT = "WEB_EVENT", TIMER_EVENT = "TIMER_EVENT", SHEDULE_EVENT = "SHEDULE_EVENT", BUS_EVENT = "BUS_EVENT", DRIVER = "DRIVER"}


------------------ Private functions ------------------

------------------ Internal API functions ------------------

function scripts_private.get_list(data)
   local processed_table, raw_table = {}

   raw_table = scripts_private.storage.index.type:select(data.type)
   for _, tuple in pairs(raw_table) do
      local processed_tuple = {
         uuid = tuple["uuid"],
         type = tuple["type"],
         name = tuple["name"],
         status = tuple["status"],
         status_msg = tuple["status_msg"],
         active_flag = tuple["active_flag"],
         specific_data = tuple["specific_data"]
      }
      table.insert(processed_table, processed_tuple)
   end
   return processed_table
end

function scripts_private.get(data)
   local tuple = scripts_private.storage.index.uuid:get(data.uuid)

   if (tuple ~= nil) then
      local table = {
         uuid = tuple["uuid"],
         type = tuple["type"],
         name = tuple["name"],
         body = tuple["body"],
         status = tuple["status"],
         status_msg = tuple["status_msg"],
         active_flag = tuple["active_flag"],
         specific_data = tuple["specific_data"]
      }
      return table
   else
      return nil
   end
end

function scripts_private.update(data)
   if (data.uuid == nil) then return nil end
   if (scripts_private.storage.index.uuid:select(data.uuid) == nil) then return nil end

   if (data.name ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 3, data.name}}) end
   if (data.body ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 4, data.body}}) end
   if (data.status ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 5, data.status}}) end
   if (data.status_msg ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 6, data.status_msg}}) end
   if (data.active_flag ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 7, data.active_flag}}) end
   if (data.specific_data ~= nil) then scripts_private.storage.index.uuid:update(data.uuid, {{"=", 8, data.specific_data}}) end

   return scripts_private.get({uuid = data.uuid})
end

function scripts_private.create(data)
   if (data.type == nil) then return nil end
   local new_data = {}
   new_data.uuid = uuid_lib.str()
   new_data.type = data.type
   new_data.name = data.name or data.uuid
   new_data.body = data.body or "\n"
   new_data.status = data.status or scripts.statuses.STOPPED
   new_data.status_msg = data.status_msg or "New script"
   new_data.active_flag = data.active_flag or scripts.flag.NON_ACTIVE
   new_data.specific_data = data.specific_data or {}
   local table = {
      new_data.uuid,
      new_data.type,
      new_data.name,
      new_data.body,
      new_data.status,
      new_data.status_msg,
      new_data.active_flag,
      new_data.specific_data
   }
   scripts_private.storage:insert(table)
   return scripts_private.get({uuid = new_data.uuid}) or "no."
end

function scripts_private.delete(data)
   return scripts_private.storage.index.uuid:delete(data.uuid)
end

------------------ HTTP API functions ------------------


function scripts_private.http_api_get_list(params, req)
   local table = scripts_private.get_list({type = params["type"]})
   return req:render{ json = table }
end


function scripts_private.http_api_create(params, req)
   if (params["name"] ~= nil and params["name"] ~= "" and params["type"] ~= nil and scripts.type[params["type"]] ~= nil) then
      local table = scripts_private.create({type = params["type"], name = params["name"], status = params["status"], status_msg = params["status_msg"]})
      return req:render{ json = table }
   else
      return req:render{ json = {error = true, error_msg = "Script API Create: no name or type"} }
   end
end


function scripts_private.http_api_delete(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      if (scripts_private.get({uuid = params["uuid"]}) ~= nil) then
         local table = scripts_private.delete({uuid = params["uuid"]})
         return req:render{ json = table }
      else
         return req:render{ json = {error = true, error_msg = "Script API Delete: UUID not found"} }
      end
   else
      return req:render{ json = {error = true, error_msg = "Script API Delete: no UUID"} }
   end
end


function scripts_private.http_api_get(params, req)
   if (params["uuid"] ~= nil and params["uuid"] ~= "") then
      local table = scripts_private.get({uuid = params["uuid"]})
      if (table ~= nil) then
         return req:render{ json = table }
      else
         return req:render{ json = {error = true, error_msg = "UUID not found"} }
      end
   else
      return req:render{ json = {error = true, error_msg = "Script API Get: no UUID"} }
   end
end


function scripts_private.http_api_update(params, req)
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         if (scripts_private.get({uuid = params["uuid"]}) ~= nil) then
            local data = {}
            data.uuid = params["uuid"]
            data.name = params["name"]
            data.active_flag = params["active_flag"]
            local _,_, base_64_string = string.find(params["body"] or "", "data:text/plain;base64,(.+)")
            if (base_64_string ~= nil) then
               local text_decoded = digest.base64_decode(base_64_string)
               if (text_decoded ~= nil) then
                  data.body = text_decoded
               end
            end

            local table = scripts_private.update(data)
            return req:render{ json = table }

         else
            return req:render{ json = {error = true, error_msg = "Script API Update: UUID not found"} }
         end
      else
         return req:render{ json = {error = true, error_msg = "Script API Update: no UUID"} }
      end
end


function scripts_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "get_list") then
      return_object = scripts_private.http_api_get_list(params, req)

   elseif (params["action"] == "create") then
      return_object = scripts_private.http_api_create(params, req)

   elseif (params["action"] == "delete") then
      return_object = scripts_private.http_api_delete(params, req)

   elseif (params["action"] == "get") then
      return_object = scripts_private.http_api_get(params, req)

   elseif (params["action"] == "update") then
      return_object = scripts_private.http_api_update(params, req)
   else
      return_object = req:render{ json = {error = true, error_msg = "Script API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Script API: Unknown error(213)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end




------------------ Public functions ------------------



function scripts.storage_init()
   local format = {
      {name='uuid',           type='string'},   --1
      {name='type',           type='string'},   --2
      {name='name',           type='string'},   --3
      {name='body',           type='string'},   --4
      {name='status',         type='string'},   --5
      {name='status_msg',     type='string'},   --6
      {name='active_flag',    type='string'},   --7
      {name='specific_data',  type='array'}     --8
   }
   scripts_private.storage = box.schema.space.create('scripts', {if_not_exists = true, format = format})
   scripts_private.storage:create_index('uuid', {parts = {'uuid'}, if_not_exists = true})
   scripts_private.storage:create_index('type', {parts = {'type'}, if_not_exists = true, unique = false})
end

function scripts.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/scripts", scripts_private.http_api)
end

function scripts.init()
   scripts.storage_init()
   scripts.http_init()
end

function scripts.get(data)
   return scripts_private.get({uuid = data.uuid})
end

function scripts.update(data)
   return scripts_private.update(data)
end

function scripts.get_all(data)
   if (data ~= nil and data.type ~= nil) then
      return scripts_private.get_list({type = data.type})
   else
      return {}
   end
end

return scripts














