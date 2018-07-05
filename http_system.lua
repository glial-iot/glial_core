#!/usr/bin/env tarantool
local http_system = {}

local box = box
local log = require 'log'

local system = require 'system'
local config = require 'config'

function http_system.init()
   http_system.init_server()
   http_system.init_client()
end

function http_system.init_server()
   http_system.server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})
   http_system.server:start()
end

function http_system.init_client()
   http_system.client = require('http.client')
end

function http_system.endpoint_config(path, handler)
   http_system.server:route({ path = path }, handler)
end

return http_system
