local event = {}
event.endpoint = "/data"
event.name = "generic_web_graph"
event.active = true
event.event_function = function(req)
   local ts_storage = require 'ts_storage'
   local system = require 'system'
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local table = system.reverse_table(ts_storage.object.index.serial_number:select({type_item}, {iterator = 'REQ'}))
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      i = i + 1
      data_object[i] = {}
      data_object[i].date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      data_object[i][serialNumber] = tuple[4]
      if (type_limit ~= nil and type_limit <= i) then
         break
      end
   end
   return_object = req:render{ json = data_object }
   return return_object
end
return event
