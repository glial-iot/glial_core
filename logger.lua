#!/usr/bin/env tarantool
local logger = {}
local logger_private = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box

local system = require 'system'
local config = require 'config'

logger.INFO = "INFO"
logger.WARNING = "WARNING"
logger.ERROR = "ERROR"
logger.USER = "USER"


------------------ Private functions ------------------

------------------ HTTP API functions ------------------
function logger_private.http_api_get_logs(params, req)
   local processed_table, raw_table = {}

   raw_table = logger.storage.index.key:select(nil, {iterator = 'REQ'})
   for _, tuple in pairs(raw_table) do
      repeat
         if (params["uuid"] ~= nil and params["uuid"] ~= "") then
            if (params["uuid"] ~= tuple["uuid_source"]) then
               do break end
            end
         end
         local processed_tuple = {
            key = tuple["key"],
            level = tuple["level"],
            source = tuple["source"],
            uuid_source = tuple["uuid_source"],
            entry = tuple["entry"],
            epoch = tuple["epoch"],
            trace = tuple["trace"],
            date_abs = os.date("%Y-%m-%d, %H:%M:%S", tuple["epoch"]),
            date_rel = (system.format_seconds(os.time() - tuple["epoch"])).." ago"
         }
         table.insert(processed_table, processed_tuple)
      until true
      if (params["limit"] ~= nil and tonumber(params["limit"]) <= #processed_table) then break end
   end
   return req:render{ json = processed_table }
end

function logger_private.http_api_delete_logs(params, req)
   logger.storage:truncate()
   logger.sequence:reset()
   return req:render{ json = { error = false } }
end

function logger_private.http_api(req)
   local return_object
   local params = req:param()
   if (params["action"] == "delete_logs") then
      return_object = logger_private.http_api_delete_logs(params, req)

   elseif (params["action"] == "get_logs") then
      return_object = logger_private.http_api_get_logs(params, req)

   else
      return_object = req:render{ json = {error = true, error_msg = "Logger API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {error = true, error_msg = "Logger API: Unknown error(224)"} }
   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

function logger.tarantool_pipe_log_handler(req)
   local body = req:read({delimiter = nil, chunk = 1000}, 10)

   local _, _, type, message = string.find(body, ".+%[.+%].+(.)>(.+)$")
   if (type ~= nil and message ~= nil and string.find(message, "(Empty input string)") == nil and string.find(body, "LOGGER:") == nil) then
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


------------------ Public functions ------------------


function logger.generate_log_functions(uuid, name)
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

   return log_error, log_warning, log_info
end

function logger.add_entry(level, source, entry, uuid_source, trace)
   local local_trace = trace or debug.traceback()
   local timestamp = os.time()
   if (level == nil) then
      return
   end

   if (level ~= logger.INFO and level ~= logger.WARNING and level ~= logger.ERROR and level ~= logger.USER) then
      return
   end

   if (entry == nil or entry == "") then
      return
   end

   logger.storage:insert{nil, level, (source or ""), (uuid_source or "No UUID"), entry, timestamp, local_trace}
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
      {name='key'                       },   --1
      {name='level',       type='string'},   --2
      {name='source',      type='string'},   --3
      {name='uuid_source', type='string'},   --4
      {name='entry',       type='string'},   --5
      {name='epoch',       type='integer'},  --6
      {name='trace',       type='string'},   --7
   }
   logger.sequence = box.schema.sequence.create("log_sequence", {if_not_exists = true})
   logger.storage = box.schema.space.create('log', {if_not_exists = true, format = format, id = config.id.logs})

   logger.storage:create_index('key', {sequence="log_sequence", if_not_exists = true})
   logger.storage:create_index('level', {parts = {'level'}, if_not_exists = true, unique = false})
   logger.storage:create_index('uuid_source', {parts = {'uuid_source'}, if_not_exists = true, unique = false})
end

function logger.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/system_logger_ext", logger.tarantool_pipe_log_handler)
   http_system.endpoint_config("/logger", logger_private.http_api)
end


return logger
