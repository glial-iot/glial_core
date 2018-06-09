#!/usr/bin/env tarantool
local webedit = {}

local fio = require 'fio'
local digest = require 'digest'
local inspect = require 'libs/inspect'

local logger = require 'logger'
local system = require 'system'
local config = require 'config'

local open = io.open

function webedit.init()
end

function webedit.item_to_address(item, name)
   local address
   address = config.dir[item]
   if (name == nil) then
      return address
   else
      if (string.find(name, ".+%..+$") == nil) then
         if (item == "html") then
            name = name..".html"
         else
            name = name..".lua"
         end
      end
      return address.."/"..name
   end
end

function webedit.get_file(item, name)
   local address = webedit.item_to_address(item, name)
   local file = open(address, "rb")
   local file_data = file:read("*a")
   file:close()
   return file_data
end

function webedit.save_file(item, name, file_data)
   local result = true
   local address = webedit.item_to_address(item, name)
   local file = open(address, "w+")
   local status = file:write(file_data)
   if (status == nil) then
       logger.add_entry(logger.ERROR, "Webedit subsystem", 'File '..address..' not save')
       result = false
   end
   file:close()
   return result
end

function webedit.delete_file(item, name)
   local address = webedit.item_to_address(item, name)
   return fio.rename(address, address..".delete")
end

function webedit.new_file(item, name)
   local address = webedit.item_to_address(item, name)
   local fh = fio.open(address, {'O_CREAT'})
   if (fh ~= nil) then
      fh:close()

      fio.chmod(address, tonumber('0755', 8))

      local file = open(address, "w+")
      file:write("\n")
      file:close()
      return true
   else
      return false
   end
end

function webedit.get_list(item)
   local data_object = {}
   local address = webedit.item_to_address(item)

   for _, file in pairs(fio.listdir(address)) do
      if (string.find(file, ".+%.lua$") ~= nil or string.find(file, ".+%.html$") ~= nil) then
         local _, _, name = string.find(file, "(.+)%..+$")
         table.insert(data_object, {name = name})
      end
   end
   return data_object
end

function webedit.http_handler_v3(req)
   local params = req:param()
   local return_object = req:render{ json = ""  }

   if (params["action"] == "get") then
      return_object = { body = webedit.get_file(params["item"], params["name"]) }

   elseif (params["action"] == "save" and params["value"] ~= nil) then
      local _,_, base_64_string = string.find(params["value"], "data:text/plain;base64,(.+)")
      local text_decoded
      if (base_64_string ~= nil) then
         text_decoded = digest.base64_decode(base_64_string)
         if (text_decoded ~= nil) then
            return_object = req:render{ json = { result = webedit.save_file(params["item"], params["name"], text_decoded)} }
         end
      end

   elseif (params["action"] == "delete") then
      return_object = req:render{ json = { result = webedit.delete_file(params["item"], params["name"])} }

   elseif (params["action"] == "new") then
      return_object = req:render{ json = { result = webedit.new_file(params["item"], params["name"]) } }

   elseif (params["action"] == "get_list") then
      return_object = req:render{ json = webedit.get_list(params["item"])  }
   end

   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

return webedit
