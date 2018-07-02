#!/usr/bin/env tarantool
local t = {}
local t_private = {}

local box = box
local http_system = require 'http_system'
local uuid_lib = require('uuid')
local digest = require 'digest'


local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local statuses = {ERROR = "ERROR", WARNING = "WARNING", NORMAL = "NORMAL", STOPPED = "STOPPED"}
local flag = {START = "START", NOT_START = "NOT_START"}

local script_bodies = {}

------------------ Private functions ------------------

function t_private.get(data)
end

function t_private.update(data)

end

function t_private.create(data)

end

function t_private.delete(data)
end

function t_private.get_all()

end







------------------ Public functions ------------------

function t.init()

end

function t.start()
end



return t























--[[ function scripts_drivers_private.load_script(uuid)
   script_bodies[uuid] = nil
   local script_params = scripts_drivers_private.get_script(uuid)
   if (script_params.start_flag == nil or script_params.start_flag ~= flag.START) then
      logger.add_entry(logger.INFO, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (non-active)')
      scripts_drivers_private.set_script(uuid, {status = statuses.STOPPED, status_msg = 'stopped'})
      return true
   end

   if (script_params.uuid == nil) then
      return false
   end
   if (script_params.body == nil) then
      return false
   end

   local current_func, error_msg = loadstring(script_params.body)


   if (current_func == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (loadstring error: '..(error_msg or "")..')')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'start: load error: '..(error_msg or "")})
      return false
   end

   script_bodies[uuid] = setmetatable({}, {__index=_G})
   local status, err_msg = pcall(setfenv(current_func, script_bodies[uuid]))
   if (status ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (load error: '..(err_msg or "")..')')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'start: load error: '..(err_msg or "")})
      return false
   end

   if (script_bodies[uuid].init == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (init function not found)')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'start: init function not found'})
      return false
   end

   if (script_bodies[uuid].destroy == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (destroy function not found)')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'start: destroy function not foundr'})
      return false
   end

   status, err_msg = pcall(script_bodies[uuid].init)

   if (status ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not start (init function error: '..(err_msg or "")..')')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'start: destroy function error: '..(data or "")})
      return false
   end

   logger.add_entry(logger.INFO, "Drivers subsystem", 'Driver "'..script_params.name..'" start (active)')
   scripts_drivers_private.set_script(uuid, {status = statuses.NORMAL, status_msg = 'start (active)'})
end

function scripts_drivers_private.unload_script(uuid)
   local script_body = script_bodies[uuid]
   local script_params = scripts_drivers_private.get_script(uuid)
   if (script_body == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not stop (script body error)')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'stop: script body error'})
      return false
   end
   if (script_body.init == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not stop (init function not found)')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'stop: init function not found'})
      return false
   end
   if (script_body.destroy == nil) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not stop (destroy function not found)')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'stop: destroy function not found'})
      return false
   end
   local destroy_result, data = pcall(script_body.destroy()) -- что возвращает pcall?
   if (destroy_result ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..script_params.name..'" not stop (destroy function error: '..(data or "")..')')
      scripts_drivers_private.set_script(uuid, {status = statuses.ERROR, status_msg = 'stop: destroy function error: '..(data or "")})
      return false
   end
   scripts_drivers_private.set_script(uuid, {status = statuses.STOPPED, status_msg = 'stopped'})
   script_bodies[uuid] = nil
   return true
end


function scripts_drivers_private.get_all_scripts_params()
   local table = scripts_drivers.storage.index.uuid:select(nil, {iterator = 'EQ'})
   return table
end

function scripts_drivers.start(dir_path)
   for _, tuple in scripts_drivers.storage.index.uuid:pairs() do
      local uuid = tuple[1]
      scripts_drivers.storage.index.uuid:update(uuid, {{"=", 4, statuses.ERROR}})
   end

   local files = system.get_files_in_dir(dir_path, ".+%.lua")

   for i, path in pairs(files) do
      local _, _, uuid_in_filename = string.find(path, ".+/(.+-.+-.+-.+-.+).lua")
      scripts_drivers.load_script(uuid_in_filename)
   end

end

function scripts_drivers_private.get_params_by_uuid(uuid)
   local table = scripts_drivers.storage.index.uuid:select(uuid, {iterator = 'EQ', limit = 1})
   if (table[1] ~= nil) then
      return {uuid = table[1][1], path = table[1][2], name = table[1][3], error_flag = table[1][4], start_flag = table[1][5]}
   end
end

function scripts_drivers_private.get_or_add_params_by_path(path)
   local table = scripts_drivers.storage.index.path:select(path, {iterator = 'EQ', limit = 1})
   if (table[1] ~= nil) then
      return {uuid = table[1][1], path = table[1][2], name = table[1][3], error_flag = table[1][4], start_flag = table[1][5]}
   else
      local script_uuid = uuid_lib.str()
      local name = "undefined"
      local error_flag, start_flag = false, false
      scripts_drivers.storage:insert{script_uuid, path, name, error_flag, start_flag}
      return {uuid = script_uuid, path = path, name = name, error_flag = error_flag, start_flag = start_flag}
   end
end
--test

function scripts_drivers_private.set_params(driver_uuid, params)
   if (driver_uuid ~= nil) then
      if (params.name ~= nil) then
         scripts_drivers.storage.index.uuid:update(driver_uuid, {{"=", 3, params.name}})
      end
      if (params.error_flag ~= nil) then
         scripts_drivers.storage.index.uuid:update(driver_uuid, {{"=", 4, params.error_flag}})
      end
      if (params.start_flag ~= nil) then
         scripts_drivers.storage.index.uuid:update(driver_uuid, {{"=", 5, params.start_flag}})
      end
      return true
   end
   return false
end

function scripts_drivers.unload_script(uuid)
   if (functions[uuid].ftable.init == nil) then
      return true
   end

   local status, err_msg = pcall(functions[uuid].ftable.destroy)

   if (status ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..functions[uuid].ftable.name..'" not stop (destroy function error: '..(err_msg or "")..')')
      scripts_drivers_private.set_params(uuid, {error_flag = true})
      return false
   end

      logger.add_entry(logger.INFO, "Drivers subsystem", 'Driver "'..params.name..'" stop')
   scripts_drivers_private.set_params(params.uuid, {error_flag = false})
end ]]

