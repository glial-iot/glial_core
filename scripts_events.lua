#!/usr/bin/env tarantool
local scripts_events = {}


scripts_events.vaisala_event = {}
scripts_events.vaisala_event.topic = "/vaisala/H2S"
function scripts_events.vaisala_event.event_function(topic, value)
   local bus = require 'bus'
   bus.update_value(topic.."_x100", value*100)
end


scripts_events.tarantool_web_graph = {}
scripts_events.tarantool_web_graph.type = scripts_events.types.HTTP
scripts_events.tarantool_web_graph.endpoint = "/tarantool-data"
scripts_events.tarantool_web_graph.event_function = function(req)
   local params = req:param()
   local data_object, i = {}, 0
   local table = ts_storage.object.index.primary:select(nil, {iterator = 'REQ'})
   --local table = ReverseTable(table)

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
      end
      if (params["limit"] ~= nil and params["limit"] <= i) then break end
   end
   return req:render{ json = data_object }
end

return scripts_events
