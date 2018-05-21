#!/usr/bin/env tarantool
local log = require 'log'
local inspect = require 'inspect'
local system = require 'system'
local box = box

local logger = {}
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

function logger.add_entry(level, source, entry)
   local trace = debug.traceback()
   local timestamp = os.time()
   logger.storage:insert{nil, level, (source or ""), entry, timestamp, trace}
end

function logger.return_all_entry(req)
   local params = req:param()
   local data_object, i = {}, 0

   local table = logger.storage.index.key:select(nil, {iterator = 'REQ'})

   for _, tuple in pairs(table) do
      local key = tuple[1]
      local level = tuple[2]
      local source = tuple[3]
      local entry = tuple[4]
      local epoch = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", epoch)

      if (params["item"] == "ALL" or params["item"] == level) then
         i = i + 1
         data_object[i] = {}
         data_object[i].key = key
         data_object[i].level = level
         data_object[i].source = source
         data_object[i].entry = entry
         local diff_time = os.time() - epoch
         diff_time = system.format_seconds(diff_time)
         data_object[i].date = date.." ("..(diff_time).." ago)"
         if (params["limit"] ~= nil and tonumber(params["limit"]) <= i) then break end
      end
   end
   return req:render{ json = data_object }
end

function logger.delete_logs()
   logger.storage:truncate()
   logger.sequence:reset()
end

function logger.actions(req)
   local params = req:param()
   if (params["action"] == "delete_logs") then
      logger.delete_logs()
   end
   return req:render{ json = { result = true } }
end

function logger.tarantool_pipe_log_handler(req)
   local body = req:read({delimiter = nil, chunk = 1000}, 10)
   local _, _, type, message = string.find(body, ".+%[.+%].+(.)>(.+)$")
   if (type ~= nil and message ~= nil and string.find(message, "(Empty input string)") == nil) then
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
