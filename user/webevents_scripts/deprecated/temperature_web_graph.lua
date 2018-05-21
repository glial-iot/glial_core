local event = {}
event.endpoint = "/temperature-data"
event.name = "temperature_web_graph"
event.active = true
event.event_function = function(req)

   local ts_storage = require 'ts_storage'
   local system = require 'system'
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local table = system.reverse_table(ts_storage.object.index.primary:select(nil, {iterator = 'REQ'}))
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      if (type_item == "local") then
         if (serialNumber == "28-000008e7f176" or serialNumber == "28-000008e538e6") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(tuple[4])
         end
      end
      if (type_limit ~= nil and type_limit <= i) then break end
   end
   return_object = req:render{ json = data_object }
   return return_object
end

return event
