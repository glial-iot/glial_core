local driver = {}
driver.name = "mercury"
driver.active = true
driver.driver_function = function()
   local mqtt = require 'mqtt'
   local config = require 'config'
   local socket = require 'socket'
   local bus = require 'bus'

   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, local_topic, item = string.find(topic, "(/devices/mercury200.+/controls/)(.+)$")
      if (local_topic ~= nil and payload ~= nil) then
         bus.update_value_average("/mercury200/"..item, tonumber(payload), 10)
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
         mqtt_object:subscribe('/devices/mercury200.02_34892924/controls/+', 0)
      end
   else
      error('Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed')
   end
end
return driver
