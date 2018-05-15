#!/usr/bin/env tarantool
local system = require 'system'
local http_client = require('http.client')

local stdin = io.stdin:lines()

for line in stdin do
   print(line)
   http_client.post('http://127.0.0.1:8080/system_logger_ext', line)
end
