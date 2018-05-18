#!/usr/bin/env tarantool

local influx_storage = {}
local http_client = require('http.client').new({50})
local box = box
local ts_list = {}

function influx_storage.init()

end


function influx_storage.update_value(db, topic, value)
   topic = string.gsub(topic, " ", "_")
   local data = string.format('%s value=%s', topic, tonumber(value) or 0)
   local url = string.format('http://influxdb:8086/write?db=%s', db)
   local r = http_client:post(url, data, {timeout = 1})
   return r.body
end



return influx_storage

