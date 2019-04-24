#!/usr/bin/env tarantool
local http_system = {}

local box = box
local log = require 'log'

local system = require 'system'
local config = require 'config'
local digest = require 'digest'
local settings = require 'settings'


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


function http_system.return_401(req)
   local return_object
   return_object = req:render{ json = {result = false, error_msg = "API: no auth"} }
   return_object.status = 401
   return_object.headers['WWW-Authenticate'] = 'Basic realm="Glial login and pass required"';
   return_object.headers['Connection'] = 'close';

   return system.add_headers(return_object)
end


function http_system.generate_http_handler(original_handler)
   local function handler(req)
      local login_status, settings_login = settings.get("http_login")
      local pass_status, settings_password = settings.get("http_password")

      if (login_status ~= true or pass_status ~= true or settings_login == "" or settings_password == "") then
         return original_handler(req)
      end

      if (req.headers["authorization"] == nil) then return http_system.return_401(req) end

      local _, _, auth_string  = string.find(req.headers["authorization"], "Basic (.+)")
      if (auth_string == nil) then return http_system.return_401(req) end

      local basic_decoded_string = digest.base64_decode(auth_string)
      if (basic_decoded_string == nil) then return http_system.return_401(req) end

      local _, _, login, pass  = string.find(basic_decoded_string, "(.+):(.+)")
      if (login == nil or pass == nil) then return http_system.return_401(req) end

      if (login ~= settings_login or pass ~= settings_password) then
         return http_system.return_401(req)
      else
         return original_handler(req)
      end
   end
   return handler
end

function http_system.endpoint_config(path, handler)
   local generated_hadler = http_system.generate_http_handler(handler)
   http_system.server:route({ path = path }, generated_hadler)
end

return http_system
