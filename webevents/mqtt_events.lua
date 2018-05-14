local event = {}
event.endpoint = "/action"
event.name = "mqtt_events"
event.active = true
event.event_function = function(req)

   local mqtt_local = require 'mqtt'
   local logger = require 'logger'
   local config = require 'config'
   local socket = require 'socket'
   local params = req:param()

   if (params["action"] ~= nil) then

      if (params["action"] == "tarantool_stop") then
         logger.add_entry(logger.INFO, "Action events", 'System stop on web control page')
         os.exit()
      elseif (params["action"] == "wipe_storage") then
         os.execute("rm -rf ./db/*")
         os.exit()
      end

      local result, emessage
      local conn = socket.tcp_connect(config.MQTT_WIRENBOARD_HOST, config.MQTT_WIRENBOARD_PORT, 2)
      if (conn ~= nil) then
         conn:close()
         local mqtt_object = mqtt_local.new(config.MQTT_WIRENBOARD_ID.."_action_driver", true)
         mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt_local.LOG_ALL})
         if (params["action"] == "on_light_1") then
            result, emessage = mqtt_object:publish("/devices/noolite_tx_0x290/controls/state/on", "1", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "off_light_1") then
            result, emessage = mqtt_object:publish("/devices/noolite_tx_0x290/controls/state/on", "0", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "on_light_2") then
            result, emessage = mqtt_object:publish("/devices/noolite_tx_0x291/controls/state/on", "1", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "off_light_2") then
            result, emessage = mqtt_object:publish("/devices/noolite_tx_0x291/controls/state/on", "0", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "on_ac") then
            result, emessage = mqtt_object:publish("/devices/wb-mr6c_105/controls/K4/on", "1", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "off_ac") then
            result, emessage = mqtt_object:publish("/devices/wb-mr6c_105/controls/K4/on", "0", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "on_fan") then
            result, emessage = mqtt_object:publish("/devices/wb-mr6c_105/controls/K5/on", "1", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         elseif (params["action"] == "off_fan") then
            result, emessage = mqtt_object:publish("/devices/wb-mr6c_105/controls/K5/on", "0", mqtt_local.QOS_1, mqtt_local.NON_RETAIN)
         end
      else
         logger.add_entry(logger.ERROR, event.name, 'Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed')
         result = false
         emessage = 'Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed'
      end
      if (result ~= true) then
         logger.add_entry(logger.ERROR, event.name, 'Send MQTT message to host '..config.MQTT_WIRENBOARD_HOST..' failed: '..(emessage or "no emessage"))
      end
      return req:render{ json = { result = result, msg = emessage } }
   end
end

return event
