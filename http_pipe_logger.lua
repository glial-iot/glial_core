#!/usr/bin/env tarantool
local http_client = require('http.client').new({max_connections = 5})
local stdin = io.stdin:lines()
local port = os.getenv('PORT') or "8080"

for line in stdin do
   http_client.post('http://127.0.0.1:'..port..'/system_logger_ext', line, {timeout = 1})
end
