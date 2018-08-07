#!/usr/bin/env tarantool

local export = {}
local http_client = require('http.client').new({50})
local fiber = require 'fiber'
local box = box

local logger = require 'logger'


local influx_count = 0

function export.init()
   export.export_rps_stat_worker_fiber = fiber.create(export.export_rps_stat_worker)
end


function export.send_value(topic, value)
   export.influx(topic, value)

end

function export.influx(topic, value)
   value = tonumber(value)
   if (value ~= nil) then
      local data = string.format('%s value=%s', topic:gsub(" ", "_"), tonumber(value) or 0)
      local r = http_client:post('http://influxdb:8086/write?db=glue', data, {timeout = 1})
      if (r.body ~= nil) then
         logger.add_entry(logger.ERROR, "Influx-export", 'Answer: '..r.body)
      else
         influx_count = influx_count + 1

      end
   end
end


function export.export_rps_stat_worker()
   local bus = require 'bus'
   while true do
      bus.update_value("/glue/export/influx_count", influx_count)
      fiber.sleep(5)
   end
end



return export

