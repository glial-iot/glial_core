#!/usr/bin/env tarantool
local scripts_drivers = {}
local bus = require 'bus'
local log = require 'log'

function scripts_drivers.map12h_driver()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local function map12h_driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, sensor_address = string.find(topic, "/devices/wb%-map12h_156/controls/(.+)$")
      if (sensor_address ~= nil and payload) then
         local local_topic = "/wb-map12h/"..sensor_address
         bus.update_value(local_topic, tonumber(payload))
      end
   end

   local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_map12h_driver", true)
   local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_status ~= true) then
      print ("MQTT(map12h_driver) error: "..(mqtt_err or "unknown error"))
   else
      mqtt_object:on_message(map12h_driver_mqtt_callback)

      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L1', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L2', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L3', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 Total P', 0)

      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L1', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L2', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L3', 0)

      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L1', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L2', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L3', 0)

      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Urms L1', 0)
      mqtt_object:subscribe('/devices/wb-map12h_156/controls/Frequency', 0)
   end
end


function scripts_drivers.vaisala_driver()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, vaisala_sensor_topic = string.find(topic, "(/devices/vaisala/data)")
      if (vaisala_sensor_topic ~= nil and payload ~= nil) then
         local vaisala_data = {}
         _, _, vaisala_data.STATa, vaisala_data.Ta, vaisala_data.RHa, vaisala_data.PAa, vaisala_data.NO2, vaisala_data.SO2, vaisala_data.CO, vaisala_data.H2S, vaisala_data.PM25, vaisala_data.PM10, vaisala_data.STATw, vaisala_data.WD, vaisala_data.WDMAX, vaisala_data.WDMIN, vaisala_data.WS, vaisala_data.WSMAX, vaisala_data.WSMIN, vaisala_data.Tw, vaisala_data.RHw, vaisala_data.PAw, vaisala_data.Ha, vaisala_data.Hd, vaisala_data.Hi, vaisala_data.Ra_mm, vaisala_data.Ra_s, vaisala_data.Ra_mmh  = string.find(payload, "STATa=(%d+%.?%d*), Ta=(%d+%.?%d*)oC, RHa=(%d+%.?%d*)%%, PAa=(%d+%.?%d*)mbar, NO2=(%d+%.?%d*).g/m3, SO2=(%d+%.?%d*).g/m3, CO=(%d+%.?%d*).g/m3, H2S=(%d+%.?%d*).g/m3, PM2.5=(%d+%.?%d*).g/m3, PM10=(%d+%.?%d*).g/m3, STATw=(%d+%.?%d*), WD=(%d+)dir, WDMAX=(%d+)dir, WDMIN=(%d+)dir, WS=(%d+%.?%d*)m/s, WSMAX=(%d+%.?%d*)m/s, WSMIN=(%d+%.?%d*)m/s, Tw=(%d+%.?%d*)oC, RHw=(%d+%.?%d*)%%, PAw=(%d+%.?%d*)mm Hg, Ha=(%d+%.?%d*)mm , Hd=(%d+%.?%d*)s , Hi=(%d+%.?%d*)mm/h, Ra=(%d+%.?%d*)mm, Ra=(%d+%.?%d*)s, Ra=(%d+%.?%d*)mm/h")

         for value_name, value_data in pairs(vaisala_data) do
            local local_topic = "/vaisala/"..value_name
            bus.update_value(local_topic, tonumber(value_data))
         end

      end
   end

   local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_vaisala_driver", true)
   local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_status ~= true) then
      print ("MQTT(vaisala_driver) error: "..(mqtt_err or "unknown error"))
   else
      mqtt_object:on_message(driver_mqtt_callback)
      mqtt_object:subscribe('/devices/vaisala/data', 0)
   end
end


function scripts_drivers.mercury_driver()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, local_topic, item = string.find(topic, "(/devices/mercury200.+/controls/)(.+)$")
      if (local_topic ~= nil and payload ~= nil) then
         bus.update_value("/mercury200/"..item, tonumber(payload))
      end
   end

   local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_mercury_driver", true)
   local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_status ~= true) then
      print ("MQTT(mercury_driver) error: "..(mqtt_err or "unknown error"))
   else
      mqtt_object:on_message(driver_mqtt_callback)
      mqtt_object:subscribe('/devices/mercury200.02_34892924/controls/+', 0)
   end
end


function scripts_drivers.wirenboard_driver()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, device, item = string.find(topic, "/devices/(.+)/controls/(.+)$")
      if (device ~= nil and item ~= nil and item ~= payload) then
         bus.update_value("/"..device.."/"..item, tonumber(payload))
      end
   end

   local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_wirenboard_driver", true)
   local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_status ~= true) then
      print ("MQTT(wirenboard_driver) error: "..(mqtt_err or "unknown error"))
   else
      mqtt_object:on_message(driver_mqtt_callback)
      mqtt_object:subscribe('/devices/wb-w1/controls/+', 0)

      mqtt_object:subscribe('/devices/wb-mr6c_105/controls/Input 6 counter', 0)

      mqtt_object:subscribe('/devices/wb-adc/controls/Vin', 0)
   end
end


function scripts_drivers.tarantool_stat_driver()
   local fiber = require 'fiber'

   local function system_stats()
      while true do
         local stats = box.slab.info()
         local _, arena_used_ratio_number, quota_used_ratio_number
         _, _, arena_used_ratio_number = string.find(stats.arena_used_ratio, "(.+)%%$")
         _, _, quota_used_ratio_number = string.find(stats.quota_used_ratio, "(.+)%%$")
         bus.update_value("/tarantool/arena_used_ratio", tonumber(arena_used_ratio_number))
         bus.update_value("/tarantool/arena_size", tonumber(stats.arena_size)/1000/1000)
         bus.update_value("/tarantool/arena_used", tonumber(stats.arena_used)/1000/1000)
         bus.update_value("/tarantool/quota_used_ratio", tonumber(quota_used_ratio_number))
         fiber.sleep(10)
      end
   end
   fiber.create(system_stats)
end


function scripts_drivers.start()
   for name, func in pairs(scripts_drivers) do
      if (name ~= "start") then
         func()
         log.warn("Started "..name)
      end
   end
end

return scripts_drivers
