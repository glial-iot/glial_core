#!/usr/bin/env tarantool
local webedit = {}
local logger = require 'logger'
local inspect = require 'inspect'
local fio = require 'fio'



function webedit.main(req)
   local param_item = req:param("item")
   local param_adress = req:param("address")

   if (param_item == "get") then
      local fh = fio.open(param_adress)
      local file_data = fh:read()
      fh:close()
      return { body = file_data }
   elseif (param_item == "save") then
      local result
      local fh = fio.open(param_adress, {"O_RDWR", "O_CREAT", "O_SYNC"})
      result = fh:write(req.post_params.file)
      if (result == false) then
          logger.add_entry(logger.ERROR, "Webedit subsystem", 'File '..param_adress..' not save')
      end
      fh:close()
      return req:render{ json = { result = result} }
   elseif (param_item == "get_list") then
      local data_object = {}
      for i, item in pairs(fio.listdir(param_adress)) do
         data_object[i] = {}
         data_object[i].name = item
         data_object[i].address = param_adress.."/"..item
      end
      return req:render{ json = data_object  }
   end


end

return webedit
