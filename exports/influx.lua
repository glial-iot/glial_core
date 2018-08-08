#!/usr/bin/env tarantool

local influx = {}

local box = box
local http_client = require('http.client').new({50})

local settings = require 'settings'
local logger = require 'logger'
local fiber = require 'fiber'

influx.count = 0
influx.STATUS_SETTINGS_NAME = "influx_save"
influx.INFLUX_ADDRESS = "http://influxdb:8086"
influx.UTC_OFFSET = 3

function influx.init()
   fiber.create(influx.rps_stat_worker)
   influx.create_database()
end

function influx.create_database()
   http_client:post(influx.INFLUX_ADDRESS..'/query', "q=CREATE DATABASE glue", {timeout = 1})
end

function influx.send_value(topic, value, timestamp)
   local status, settings_value = settings.get(influx.STATUS_SETTINGS_NAME, "false")
   if (status == false or settings_value == "false") then return end
   local value_number = tonumber(value)
   if (value_number ~= nil) then
      local time_utc_nanoseconds = ""
      if (timestamp ~= nil) then
         local time_utc = timestamp-(influx.UTC_OFFSET*60*60)
         time_utc_nanoseconds = tostring(time_utc*1000*1000)
      end
      local topic_no_spaces = topic:gsub(" ", "_")
      local data = string.format('%s value=%s %s', topic_no_spaces, value_number, time_utc_nanoseconds)
      local r = http_client:post(influx.INFLUX_ADDRESS..'/write?db=glue', data, {timeout = 1})
      if (r.body ~= nil) then
         logger.add_entry(logger.ERROR, "Influx-export", 'Answer: '..r.body)
      else
         influx.count = influx.count + 1
      end
   end
end

function influx.get_status()
   local status, value = settings.get(influx.STATUS_SETTINGS_NAME, "false")
   if (value == "true") then value = true else value = false end
   return value
end


function influx.set_status(status)
   if (status == "false" or status == "true") then
      settings.set(influx.STATUS_SETTINGS_NAME, status)
   end
end


function influx.rps_stat_worker()
   local bus = require 'bus'
   while true do
      bus.update_value("/glue/export/influx_count", influx.count)
      fiber.sleep(10)
   end
end



return influx

