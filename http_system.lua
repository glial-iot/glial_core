#!/usr/bin/env tarantool

local log = require 'log'
local logger = require 'logger'
local scripts_events = require 'scripts_events'
local system = require 'system'
local config = require 'config'
local box = box

local http_system = {}
http_system.proto_menu = {}
http_system.json_menu_v2 = {}


function http_system.init_server()
   http_system.server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})
   http_system.server:start()
end

function http_system.init_client()
   http_system.client = require('http.client')
end

function http_system.enpoints_menu_config(menu_list, prefix)
   if menu_list == nil then
      return
   end
   for i, item in pairs(menu_list) do
      local file_path
      if (item.file ~= nil) then
         file_path = prefix.."/"..item.file
      end
      http_system.server:route({ path = item.href, file = file_path }, item.handler)
      if (item.name ~= nil) then
         http_system.proto_menu[#http_system.proto_menu+1] = {href = item.href, name=item.name, icon=item.icon}
      end
   end
end

function http_system.enpoints_menu_for_json_generate_v2(menu_list)
   if menu_list == nil then
      return
   end
   local local_menu = {}
   local i = 1
   for _, item in pairs(menu_list) do

      if (item.name ~= nil and item.icon ~= nil and item.href ~= nil) then
         local_menu[i] = {}
         local_menu[i].href = item.href
         local_menu[i].icon = item.icon
         local_menu[i].name = item.name
         i = i + 1
      end
   end
   return local_menu
end

function http_system.menu_json_handler(req)
   return req:render{ json = http_system.json_menu_v2 }
end

function http_system.endpoint_config(path, handler)
   http_system.server:route({ path = path }, handler)
end

function http_system.generic_page_handler(req)
   local _, _, host = string.find(req.headers.host, "(.+):8080")
   local menu = {}
   for i, item in pairs(http_system.proto_menu) do
      menu[i] = {}
      menu[i].href=item.href
      menu[i].name=item.name
      menu[i].icon=item.icon
      if (item.href == req.path) then
         menu[i].class="active"
      end
   end
   return req:render{ menu = menu, git_version = system.git_version(), host = host }
end


return http_system
