#!/usr/bin/env tarantool

local log = require 'log'
local logger = require 'logger'
local scripts_events = require 'scripts_events'
local system = require 'system'
local config = require 'config'

local http_system = {}
local box = box
http_system.proto_menu = {}


function http_system.init_server()
   http_system.server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})
   http_system.server:start()
end

function http_system.init_client()
   http_system.client = require('http.client')
end

function http_system.enpoints_menu_config(endpoints_list)
   for i, item in pairs(endpoints_list) do
      http_system.server:route({ path = item[1], file = item[2] }, item[4])
      if (item[3] ~= nil) then
         http_system.proto_menu[#http_system.proto_menu+1] = {href = item[1], name=item[3], icon=item[5]}
      end
   end
end

function http_system.page_handler(req)
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
