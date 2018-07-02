#!/usr/bin/env tarantool
local logger = {}

local log = require 'log'
local inspect = require 'libs/inspect'
local box = box

local system = require 'system'

logger.INFO = "INFO"
logger.WARNING = "WARNING"
logger.ERROR = "ERROR"
logger.USER = "USER"

function logger.init()
   logger.storage = box.schema.space.create('logger_storage_2', {if_not_exists = true})
   logger.sequence = box.schema.sequence.create("logger_storage_sequence", {if_not_exists = true})
   logger.storage:create_index('key', {sequence="logger_storage_sequence", if_not_exists = true})
   logger.storage:create_index('level', {type = 'tree', unique = false, parts = {2, 'string'}, if_not_exists = true })
   logger.storage:create_index('source', {type = 'tree', unique = false, parts = {3, 'string'}, if_not_exists = true })
end

function logger.http_init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/system_logger_ext", logger.tarantool_pipe_log_handler)
   http_system.endpoint_config("/system_logger_action", logger.actions)
end

function logger.add_entry(level, source, entry)
   local trace = debug.traceback()
   local timestamp = os.time()
   logger.storage:insert{nil, level, (source or ""), entry, timestamp, trace}
   if (level == logger.INFO) then
      log.info("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.WARNING) then
      log.warn("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   elseif (level == logger.ERROR) then
      log.error("LOGGER:"..(source or "")..":"..(entry or "no entry"))
   end
end

function logger.delete_logs()
   logger.storage:truncate()
   logger.sequence:reset()
end

function logger.actions(req)
   local return_object = {}
   local params = req:param()
   if (params["action"] == "delete_logs") then
      logger.delete_logs()
      return_object = req:render{ json = { result = true } }

   elseif (params["action"] == "get_logs") then
      local data_object = {}
      local local_table = logger.storage.index.key:select(nil, {iterator = 'REQ'})
      for _, tuple in pairs(local_table) do
         local key = tuple[1]
         local level = tuple[2]
         local source = tuple[3]
         local entry = tuple[4]
         local epoch = tuple[5]
         local trace = tuple[6]

         local date_abs = os.date("%Y-%m-%d, %H:%M:%S", epoch)
         local diff_time = os.time() - epoch
         local date_rel = (system.format_seconds(diff_time)).." ago"
         table.insert(data_object, {key = key, level = level, source = source, entry = entry, date_abs = date_abs, date_rel = date_rel, trace = trace})
         if (params["limit"] ~= nil and tonumber(params["limit"]) <= #data_object) then break end
      end
      return_object = req:render{ json = data_object }
   end
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

return logger
