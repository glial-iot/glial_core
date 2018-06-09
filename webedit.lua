#!/usr/bin/env tarantool
local webedit = {}

local fio = require 'fio'
local digest = require 'digest'
local inspect = require 'libs/inspect'

local logger = require 'logger'
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

function webedit.get_list(address)
   local data_object = {}
   for _, item in pairs(fio.listdir(address)) do
      if (string.find(item, ".+%.lua$") ~= nil or string.find(item, ".+%.html$") ~= nil) then
         table.insert(data_object, {name = item, address = address.."/"..item})
      end
   end
   return data_object
end

function webedit.http_handler(req)
   local params = req:param()

   if (params["item"] == "get") then
      return { body = webedit.get_file(params["address"]) }

   elseif (params["item"] == "save") then
      return req:render{ json = { result = webedit.save_file(params["address"], req.cached_data)} }

   elseif (params["item"] == "delete") then
      return req:render{ json = { result = webedit.delete_file(params["address"])} }

   elseif (params["item"] == "new") then
      return req:render{ json = { result = webedit.new_file(params["address"]) } }

   elseif (params["item"] == "get_list") then
      return req:render{ json = webedit.get_list(params["address"])  }
   end

end


function webedit.http_handler_v2(req)
   local params = req:param()
   local return_object = req:render{ json = ""  }

   if (params["item"] == "get") then
      return_object = { body = webedit.get_file(params["address"]) }

   elseif (params["item"] == "save" and params["value"] ~= nil) then
      local _,_, base_64_string = string.find(params["value"], "data:text/plain;base64,(.+)")
      local text_decoded
      if (base_64_string ~= nil) then
         text_decoded = digest.base64_decode(base_64_string)
         if (text_decoded ~= nil) then
            return_object = req:render{ json = { result = webedit.save_file(params["address"], text_decoded)} }
         end
      end

   elseif (params["item"] == "delete") then
      return_object = req:render{ json = { result = webedit.delete_file(params["address"])} }

   elseif (params["item"] == "new") then
      return_object = req:render{ json = { result = webedit.new_file(params["address"]) } }

   elseif (params["item"] == "get_list") then
      return_object = req:render{ json = webedit.get_list(params["address"])  }
   end

   return_object.headers = return_object.headers or {}
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return return_object
end

return webedit
