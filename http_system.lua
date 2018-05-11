#!/usr/bin/env tarantool

local log = require 'log'
local logger = require 'logger'
local scripts_events = require 'scripts_events'
local system = require 'system'
local config = require 'config'

local http_system = {}
local box = box


function http_system.init_server()
   http_system.server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})
   http_system.server:start()
end

function http_system.init_client()
   http_system.client = require('http.client')
end

function http_system.enpoints_menu_config(endpoints_list)
   local proto_menu = {}
   for i, item in pairs(endpoints_list) do
      http_system.server:route({ path = item[1], file = item[2] }, item[4])
      if (item[3] ~= nil) then
         proto_menu[#proto_menu+1] = {href = item[1], name=item[3]}
      end
   end
   return proto_menu
end


return http_system
