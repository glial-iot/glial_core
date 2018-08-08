#!/usr/bin/env tarantool

local influx = {}

local box = box
local http_client = require('http.client').new({50})

local logger = require 'logger'
local fiber = require 'fiber'

influx.count = 0
influx.status = false

function influx.init()
   fiber.create(influx.rps_stat_worker)
end


function influx.send_value(topic, value)
   if (influx.status == false) then return end
   value = tonumber(value)
   if (value ~= nil) then
      local data = string.format('%s value=%s', topic:gsub(" ", "_"), tonumber(value) or 0)
      local r = http_client:post('http://influxdb:8086/write?db=glue', data, {timeout = 1})
      if (r.body ~= nil) then
         logger.add_entry(logger.ERROR, "Influx-export", 'Answer: '..r.body)
      else
         influx.count = influx.count + 1
      end
   end
end

function influx.get_status()
   return influx.status
end


function influx.set_status(status)
   influx.status = status
end


function influx.rps_stat_worker()
   local bus = require 'bus'
   while true do
      bus.update_value("/glue/export/influx_count", influx.count)
      fiber.sleep(10)
   end
end



return influx

