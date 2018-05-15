#!/usr/bin/env tarantool
local webedit = {}
local logger = require 'logger'
local inspect = require 'inspect'
local fio = require 'fio'
local digest = require 'digest'

local open = io.open

function webedit.init()
end


function webedit.http_handler(req)
   local param_item = req:param("item")
   local param_adress = req:param("address")

   if (param_item == "get") then
      --local fh = fio.open(param_adress)
      --local file_data = fh:read()
      local file = open(param_adress, "rb")
      local file_data = file:read "*a"
      file:close()
      file_data = digest.base64_encode(file_data)
      --fh:close()
      return { body = file_data }
   elseif (param_item == "save") then
      local result
      local fh = fio.open(param_adress, {"O_RDWR", "O_CREAT", "O_SYNC"})
      local file_data = digest.base64_decode(req.post_params.file)
      print(file_data)
      result = fh:write(file_data)
      if (result == false) then
          logger.add_entry(logger.ERROR, "Webedit subsystem", 'File '..param_adress..' not save')
      end
      fh:close()
      return req:render{ json = { result = result} }
   elseif (param_item == "get_list") then
      local data_object = {}
      local i = 1
      for _, item in pairs(fio.listdir(param_adress)) do
         if (string.find(item, ".+%.lua") ~= nil) then
            data_object[i] = {}
            data_object[i].name = item
            data_object[i].address = param_adress.."/"..item
            i = i + 1
         end
      end
      return req:render{ json = data_object  }
   end

end

return webedit
