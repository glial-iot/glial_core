#!/usr/bin/env tarantool
local logger = {}
local logger_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box
local clock = require 'clock'
local fiber = require 'fiber'

local system = require 'system'
local config = require 'config'

logger.INFO = "INFO"
logger.WARNING = "WARNING"
logger.ERROR = "ERROR"
logger.REBOOT = "REBOOT"
logger.USER = "USER"

local user_truncate_threshold_percent = 80

------------------↓ Private functions ↓------------------

function logger_private.log_rotate_worker()
   while true do
      local _, _, arena_used_ratio = string.find(box.slab.info().arena_used_ratio, "(.+)%%$")
      arena_used_ratio = tonumber(arena_used_ratio)

      if (arena_used_ratio > user_truncate_threshold_percent) then
         local iterator = 0
         for _, tuple in logger.storage.index.level:pairs(logger.USER) do
            logger.storage.index.timestamp:delete(tuple["timestamp"])
            iterator = iterator + 1
         end

         iterator = iterator / 1000
         logger.add_entry(logger.WARNING, "Logger", "Remove all USER level logs(arena used ratio > 80%): "..iterator.."k entries", "", "")
         fiber.sleep(50)
      end
      fiber.sleep(5)
   end
end

------------------↓ HTTP API functions ↓------------------
function logger_private.http_api_get_logs(params, req)
   local processed_table, raw_table = {}

   raw_table = logger.storage.index.timestamp:select(nil, {iterator = 'REQ'})
   for _, tuple in pairs(raw_table) do
      repeat
         if (params["uuid"] ~= nil and params["uuid"] ~= "") then
            if (params["uuid"] ~= tuple["uuid_source"] and tuple["level"] ~= logger.REBOOT) then
               do break end
            end
         end
         if (params["level"] ~= nil and params["level"] ~= "") then
            if (params["level"] == "!USER") then
               if (tuple["level"] == logger.USER) then
                  do break end
               end
            else
               if (params["level"] ~= tuple["level"] and tuple["level"] ~= logger.REBOOT and params["level"] ~= "ALL") then
                  do break end
               end
            end
         end
         local time_in_ms = tuple["timestamp"]/10
         local processed_tuple = {
            level = tuple["level"],
            source = tuple["source"],
            uuid_source = tuple["uuid_source"],
            entry = tuple["entry"],
            time_ms = math.floor(time_in_ms),
            trace = tuple["trace"],
         }
         table.insert(processed_table, processed_tuple)
      until true
      if (params["limit"] ~= nil and tonumber(params["limit"]) <= #processed_table) then break end
   end
   local return_object = req:render{ json = processed_table }
   return system.add_headers(return_object)
end

function logger_private.http_api_delete_logs(params, req)
   logger.storage:truncate()
   local return_object = req:render{ json = { result = true } }
   return system.add_headers(return_object)
end

function logger_private.http_api(req)
   local return_object
   local params = req:param()
   if (params["action"] == "delete_logs") then
      return_object = logger_private.http_api_delete_logs(params, req)

   elseif (params["action"] == "get_logs") then
      return_object = logger_private.http_api_get_logs(params, req)

   else
      return_object = req:render{ json = {result = false, error_msg = "Logger API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Logger API: Unknown error(224)"} }
   return system.add_headers(return_object)
end

function logger_private.tarantool_pipe_log_handler(req)
   local body = req:read({delimiter = nil, chunk = 1000}, 10)

   local _, _, type, message = string.find(body, ".+%[.+%].+(.)>(.+)$")
   if (
      type ~= nil and
      message ~= nil and
      string.find(message, "Empty input string") == nil and
      string.find(message, "too long WAL write") == nil and
      string.find(message, "^Tarantool.+") == nil and
      string.find(message, "^log level.+") == nil and
      string.find(body, "LOGGER:") == nil
         ) then
      if (type == "W") then
         type = logger.WARNING
      elseif (type == "E") then
         type = logger.ERROR
      elseif (type == "C") then
         type = logger.INFO
      else
         message = "("..type..")"..message
         type = logger.INFO
      end
      logger.add_entry(type, "Tarantool logs adapter", message)
   end

   return { status = 200 }
end


function logger_private.gen_id()
   local new_id = clock.realtime()*10000
   while logger.storage.index.timestamp:get(new_id) do
      new_id = new_id + 1
   end
   return new_id
end


------------------↓ Public functions ↓------------------


function logger.generate_log_functions(uuid, name)
   local function log_error(msg, ...)
      msg = system.concatenate_args(msg, ...)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.ERROR, name, msg, uuid, trace)
   end

   local function log_info(msg, ...)
      msg = system.concatenate_args(msg, ...)
      logger.add_entry(logger.INFO, name, msg, uuid, "")
   end

   local function log_warning(msg, ...)
      msg = system.concatenate_args(msg, ...)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.WARNING, name, msg, uuid, trace)
   end

   local function log_user(msg, ...)
      msg = system.concatenate_args(msg, ...)
      logger.add_entry(logger.USER, name, msg, uuid, "")
   end

   return log_error, log_warning, log_info, log_user
end

function logger.add_entry(level, source, entry, uuid_source, trace)
   if (entry == nil) then
      return
   end

   if (type(entry) == "table") then
      entry = tostring(inspect(entry))
   else
      entry = tostring(entry)
   end

   if (level ~= logger.INFO and level ~= logger.WARNING and level ~= logger.ERROR and level ~= logger.USER and level ~= logger.REBOOT) then
      return
   end

   trace = tostring(trace or debug.traceback())
   uuid_source = uuid_source or "No UUID"
   source = source or "No source"

   if (level == logger.REBOOT) then
      for _, tuple in logger.storage.index.level:pairs(logger.REBOOT) do
         logger.storage.index.timestamp:update(tuple["timestamp"], {{"=", 2, logger.INFO}})
      end
   end

   logger.storage:insert{logger_private.gen_id(), level, source, uuid_source, entry, trace}

   if (level == logger.INFO and source ~= "Tarantool logs adapter") then
      log.info("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.WARNING and source ~= "Tarantool logs adapter") then
      log.warn("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.ERROR and source ~= "Tarantool logs adapter") then
      log.error("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   end
end

function logger.storage_init()
   local format = {
      {name='timestamp',   type='number'},   --1
      {name='level',       type='string'},   --2
      {name='source',      type='string'},   --3
      {name='uuid_source', type='string'},   --4
      {name='entry',       type='string'},   --5
      {name='trace',       type='string'},   --6
   }
   logger.storage = box.schema.space.create('log', {if_not_exists = true, format = format, id = config.id.logs})

   logger.storage:create_index('timestamp', {parts = {'timestamp'}, if_not_exists = true})
   logger.storage:create_index('level', {parts = {'level'}, if_not_exists = true, unique = false})
   logger.storage:create_index('uuid_source', {parts = {'uuid_source'}, if_not_exists = true, unique = false})

   fiber.create(logger_private.log_rotate_worker)
end

function logger.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/system_logger_ext", logger_private.tarantool_pipe_log_handler)
   http_system.endpoint_config("/logger", logger_private.http_api)
end

return logger
