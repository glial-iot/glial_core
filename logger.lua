#!/usr/bin/env tarantool
local logger = {}
local logger_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box
local clock = require 'clock'

local system = require 'system'
local config = require 'config'

logger.INFO = "INFO"
logger.WARNING = "WARNING"
logger.ERROR = "ERROR"
logger.REBOOT = "REBOOT"
logger.USER = "USER"


------------------ Private functions ------------------

------------------ HTTP API functions ------------------
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
         local time_in_sec = math.ceil(tuple["timestamp"]/10000)
         local processed_tuple = {
            level = tuple["level"],
            source = tuple["source"],
            uuid_source = tuple["uuid_source"],
            entry = tuple["entry"],
            time = time_in_sec,
            trace = tuple["trace"],
            date_abs = os.date("%Y-%m-%d, %H:%M:%S", time_in_sec),
         }
         table.insert(processed_table, processed_tuple)
      until true
      if (params["limit"] ~= nil and tonumber(params["limit"]) <= #processed_table) then break end
   end
   return req:render{ json = processed_table }
end

function logger_private.http_api_delete_logs(params, req)
   logger.storage:truncate()
   return req:render{ json = { result = true } }
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
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

function logger_private.tarantool_pipe_log_handler(req)
   local body = req:read({delimiter = nil, chunk = 1000}, 10)

   local _, _, type, message = string.find(body, ".+%[.+%].+(.)>(.+)$")
   if (
      type ~= nil and
      message ~= nil and
      string.find(message, "Empty input string") == nil and
      string.find(message, "^Tarantool .+") == nil and
      string.find(message, "^log level .+") == nil and
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


------------------ Public functions ------------------


function logger.generate_log_functions(uuid, name) --TODO: не принимают несколько аргументов, сделать.
   local function log_error(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.ERROR, name, msg, uuid, trace)
   end

   local function log_info(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.INFO, name, msg, uuid, trace)
   end

   local function log_warning(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.WARNING, name, msg, uuid, trace)
   end

   local function log_user(msg)
      local trace = debug.traceback("", 2)
      logger.add_entry(logger.USER, name, msg, uuid, trace)
   end

   return log_error, log_warning, log_info, log_user
end

function logger.add_entry(level, source, entry, uuid_source, trace)
   local local_trace = trace or debug.traceback()
   if (level == nil) then
      return
   end

   if (level ~= logger.INFO and level ~= logger.WARNING and level ~= logger.ERROR and level ~= logger.USER and level ~= logger.REBOOT) then
      return
   end

   if (entry == nil or entry == "") then
      return
   end

   logger.storage:insert{logger_private.gen_id(), level, (source or ""), (uuid_source or "No UUID"), (tostring(entry) or ""), (tostring(local_trace) or "")}

   if (level == logger.INFO) then
      log.info("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.WARNING) then
      log.warn("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.ERROR) then
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
end

function logger.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/system_logger_ext", logger_private.tarantool_pipe_log_handler)
   http_system.endpoint_config("/logger", logger_private.http_api)
end


return logger
