local event = {}
event.endpoint = "/power-data"
event.name = "power_web_graph"
event.active = true
event.event_function = function(req)
   local ts_storage = require 'ts_storage'
   local system = require 'system'
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local raw_table = ts_storage.object.index.primary:select(nil, {iterator = 'REQ'})
   local table = system.reverse_table(raw_table)
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      if (type_item == "I") then
         if (serialNumber == "Ch 1 Irms L1" or serialNumber == "Ch 1 Irms L2" or serialNumber == "Ch 1 Irms L3") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(tuple[4])
         end
         if (type_limit ~= nil and type_limit <= i) then break end
      end
   end
   return_object = req:render{ json = data_object }
   return return_object
end
return event
