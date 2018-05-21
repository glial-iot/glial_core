#!/usr/bin/env tarantool
local webedit = {}
local logger = require 'logger'
local inspect = require 'libs/inspect'
local fio = require 'fio'
local system = require 'system'

local open = io.open

function webedit.init()
end

function webedit.get_file(adress)
   local file = open(adress, "rb")
   local file_data = file:read("*a")
   file:close()
   return file_data
end

function webedit.save_file(param_adress, file_data)
   local result = true
   local file = open(param_adress, "w+")
   local status = file:write(file_data)
   if (status == nil) then
       logger.add_entry(logger.ERROR, "Webedit subsystem", 'File '..param_adress..' not save')
       result = false
   end
   file:close()
   return result
end

function webedit.delete_file(address)
   return fio.rename(address, address..".delete")
end

function webedit.new_file(address)
   local result
   local fh = fio.open(address, {'O_CREAT'})
   fh:close()

   fio.chmod(address, tonumber('0755', 8))

   local file = open(address, "w+")
   file:write("\n")
   file:close()
   if (fh ~= nil) then result = true end
   return result
end

function webedit.get_list(address)
   local data_object = {}
   local i = 1
   if (system.dir_check(address) == false) then
      return data_object
   end
   for _, item in pairs(fio.listdir(address)) do
      if (string.find(item, ".+%.lua$") ~= nil or string.find(item, ".+%.html$") ~= nil) then
         data_object[i] = {}
         data_object[i].name = item
         data_object[i].address = address.."/"..item
         i = i + 1
      end
   end
   return data_object
end

function webedit.http_handler(req)
   local param_item = req:param("item")
   local param_adress = req:param("address")

   if (param_item == "get") then
      return { body = webedit.get_file(param_adress) }

   elseif (param_item == "save") then
      return req:render{ json = { result = webedit.save_file(param_adress, req.cached_data)} }

   elseif (param_item == "delete") then
      return req:render{ json = { result = webedit.delete_file(param_adress)} }

   elseif (param_item == "new") then
      return req:render{ json = { result = webedit.new_file(param_adress) } }

   elseif (param_item == "get_list") then
      return req:render{ json = webedit.get_list(param_adress)  }
   end

end

return webedit
