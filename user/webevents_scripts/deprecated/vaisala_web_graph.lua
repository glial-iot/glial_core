local event = {}
event.endpoint = "/vaisala-data"
event.name = "vaisala_web_graph"
event.active = true
event.event_function = function(req)
   local ts_storage = require 'ts_storage'
   local system = require 'system'
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local data_object, i = {}, 0
   local raw_table = ts_storage.object.index.primary:select(nil, {iterator = 'REQ'})
   local table = system.reverse_table(raw_table)

   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      local value = tuple[4]

      if (type_item == "PM") then
         if (serialNumber == "PM25" or serialNumber == "PM10") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(value)
         end
      end
      if (type_item == "PA") then
         if (serialNumber == "PAa" or serialNumber == "PAw") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(value)
         end
      end
      if (type_item == "RH") then
         if (serialNumber == "RHa" or serialNumber == "RHw") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(value)
         end
      end
      if (type_item == "T") then
         if (serialNumber == "Ta" or serialNumber == "Tw") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(value)
         end
      end
      if (type_item == "Sall") then
         if (serialNumber == "SO2" or serialNumber == "NO2" or serialNumber == "CO" or serialNumber == "H2S") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(value)
         end
      end
      if (type_limit ~= nil and type_limit <= i) then break end
   end
   return req:render{ json = data_object }
end
return event
