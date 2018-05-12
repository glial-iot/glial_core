local driver = {}
driver.name = "vaisala"
driver.active = true
driver.driver_function = function()
   local config = require 'config'
   local mqtt = require 'mqtt'
   local bus = require 'bus'
   local net_box = require 'net.box'

   local function driver_mqtt_callback(message_id, topic, payload, gos, retain)
      local _, _, vaisala_sensor_topic = string.find(topic, "(/devices/vaisala/data)")
      if (vaisala_sensor_topic ~= nil and payload ~= nil) then
         local vaisala_data = {}
         _, _, vaisala_data.STATa, vaisala_data.Ta, vaisala_data.RHa, vaisala_data.PAa, vaisala_data.NO2, vaisala_data.SO2, vaisala_data.CO, vaisala_data.H2S, vaisala_data.PM25, vaisala_data.PM10, vaisala_data.STATw, vaisala_data.WD, vaisala_data.WDMAX, vaisala_data.WDMIN, vaisala_data.WS, vaisala_data.WSMAX, vaisala_data.WSMIN, vaisala_data.Tw, vaisala_data.RHw, vaisala_data.PAw, vaisala_data.Ha, vaisala_data.Hd, vaisala_data.Hi, vaisala_data.Ra_mm, vaisala_data.Ra_s, vaisala_data.Ra_mmh  = string.find(payload, "STATa=(%d+%.?%d*), Ta=(%d+%.?%d*)oC, RHa=(%d+%.?%d*)%%, PAa=(%d+%.?%d*)mbar, NO2=(%d+%.?%d*).g/m3, SO2=(%d+%.?%d*).g/m3, CO=(%d+%.?%d*).g/m3, H2S=(%d+%.?%d*).g/m3, PM2.5=(%d+%.?%d*).g/m3, PM10=(%d+%.?%d*).g/m3, STATw=(%d+%.?%d*), WD=(%d+)dir, WDMAX=(%d+)dir, WDMIN=(%d+)dir, WS=(%d+%.?%d*)m/s, WSMAX=(%d+%.?%d*)m/s, WSMIN=(%d+%.?%d*)m/s, Tw=(%d+%.?%d*)oC, RHw=(%d+%.?%d*)%%, PAw=(%d+%.?%d*)mm Hg, Ha=(%d+%.?%d*)mm , Hd=(%d+%.?%d*)s , Hi=(%d+%.?%d*)mm/h, Ra=(%d+%.?%d*)mm, Ra=(%d+%.?%d*)s, Ra=(%d+%.?%d*)mm/h")

         for value_name, value_data in pairs(vaisala_data) do
            local local_topic = "/vaisala/"..value_name
            bus.update_value_average(local_topic, tonumber(value_data), 10)
         end

      end
   end

   local conn = net_box.connect(config.MQTT_WIRENBOARD_HOST..":"..config.MQTT_WIRENBOARD_PORT)
   if (conn.state == "connecting") then
      conn:close()
      local mqtt_object = mqtt.new(config.MQTT_WIRENBOARD_ID.."_"..driver.name, true)
      local mqtt_status, mqtt_err = mqtt_object:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
      if (mqtt_status ~= true) then
         error('MQTT error '..(mqtt_err or "unknown error"))
      else
         mqtt_object:on_message(driver_mqtt_callback)
         mqtt_object:subscribe('/devices/vaisala/data', 0)
      end
   else
      error('Connect to host '..config.MQTT_WIRENBOARD_HOST..' failed')
   end
end
return driver
