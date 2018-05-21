local driver = {}
driver.name = "map12h"
driver.active = true
driver.driver_function = function()
   local mqtt = require 'mqtt'
   local bus = require 'bus'
   local config = require 'config'
   local socket = require 'socket'

   local function mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, sensor_address = string.find(topic, "/devices/wb%-map12h_156/controls/(.+)$")
      if (sensor_address ~= nil and payload) then
         local local_topic = "/wb-map12h/"..sensor_address
         bus.update_value(local_topic, tonumber(payload))

      end
   end

   local conn = socket.tcp_connect(config.MQTT_WIRENBOARD_HOST, config.MQTT_WIRENBOARD_PORT, 2)
   if (conn ~= nil) then
      conn:close()
      local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_"..driver.name, true)
      local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
      if (mqtt_status ~= true) then
         error('MQTT error '..(mqtt_err or "unknown error"))
      else
         mqtt_object:on_message(mqtt_callback)

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
   else
      error('Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed')
   end
end
return driver
