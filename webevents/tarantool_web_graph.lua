local event = {}
event.endpoint = "/tarantool-data"
event.name = "tarantool_web_graph"
event.active = true
event.event_function = function(req)
   local ts_storage = require 'ts_storage'
   local system = require 'system'
   local params = req:param()
   local data_object, i = {}, 0
   local table = ts_storage.object.index.primary:select(nil, {iterator = 'REQ'})
   table = system.reverse_table(table)

   for _, tuple in pairs(table) do
      local topic = tuple[2]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      local value = tuple[4]

      if (params["item"] == "ratios") then
         if (topic == "/tarantool/arena_used_ratio" or topic == "/tarantool/quota_used_ratio") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][topic] = tonumber(value)
         end
      elseif (params["item"] == "mem") then
         if (topic == "/tarantool/arena_size" or topic == "/tarantool/arena_used") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][topic] = tonumber(value)
         end
      elseif (params["item"] == "tscount") then
         if (topic == "/tarantool/ts_storage_count") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][topic] = tonumber(value)
         end
      end
      if (params["limit"] ~= nil and tonumber(params["limit"]) <= i) then break end
   end
   return req:render{ json = data_object }
end
return event
