#!/usr/bin/env tarantool
local http_system = {}

local box = box
local log = require 'log'

local system = require 'system'
local config = require 'config'

function http_system.init(http_port)
   http_system.init_server(http_port)
end

function http_system.init_server(http_port)
   http_port = tonumber(http_port) or config.HTTP_PORT
   http_system.server = require('http.server').new(nil, http_port, {charset = "utf-8", app_dir = "./panel"})
   print("HTTP server runned on "..http_port.." port")
   http_system.server:route({ path = '/' }, function(req) return req:redirect_to('/panel/') end)
   http_system.server:route({ path = '/panel/', file = 'index.html' })
   http_system.server:start()
end

function http_system.endpoint_config(path, handler)
   http_system.server:route({ path = path }, handler)
end

return http_system
