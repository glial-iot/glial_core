local driver = {}
driver.name = "wirenboard"
driver.active = true
driver.driver_function = function()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local socket = require 'socket'
   local bus = require 'bus'

   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, device, item = string.find(topic, "/devices/(.+)/controls/(.+)$")
      if (device ~= nil and item ~= nil and item ~= payload) then
         bus.update_value_average("/"..device.."/"..item, tonumber(payload), 10)
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
         mqtt_object:on_message(driver_mqtt_callback)
         mqtt_object:subscribe('/devices/wb-w1/controls/+', 0)

         mqtt_object:subscribe('/devices/wb-mr6c_105/controls/Input 6 counter', 0)

         mqtt_object:subscribe('/devices/wb-adc/controls/Vin', 0)
      end
   else
      error('Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed')
   end
end
return driver
