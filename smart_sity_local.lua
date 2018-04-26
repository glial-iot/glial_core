#!/usr/bin/env tarantool
local mqtt = require 'mqtt'
local inspect = require 'inspect'
local json = require 'json'
local fiber = require 'fiber'
local impact = require 'impact'
local box = box
local impact_reports, settings

local config = require 'config'

local http_client = require('http.client')
local http_server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})

io.stdout:setvbuf("no")


local function ReverseTable(t)
    local reversedTable = {}
    local itemCount = #t
    for k, v in ipairs(t) do
        reversedTable[itemCount + 1 - k] = v
    end
    return reversedTable
end

local function impact_rest_handler(json_data)
   for i = 1, #json_data.reports do
      local subscriptionId = json_data.reports[i].subscriptionId
      local serialNumber = json_data.reports[i].serialNumber
      local resourcePath = json_data.reports[i].resourcePath
      local value = json_data.reports[i].value
      local timestamp = json_data.reports[i].timestamp

      impact_reports:insert{nil, timestamp, subscriptionId, serialNumber, resourcePath, value}

      if (resourcePath == "action/0/light") then
         if (value == "on" or value == "off") then
            if value == "on" then value = 1
            elseif value == "off" then value = 0
            end
            if (serialNumber == "NOOLITE_SK_0") then
               mqtt.wb:publish("/devices/noolite_tx_0x290/controls/state/on", value, mqtt.QOS_0, mqtt.NON_RETAIN)
            elseif (serialNumber == "NOOLITE_SK_1") then
               mqtt.wb:publish("/devices/noolite_tx_0x291/controls/state/on", value, mqtt.QOS_0, mqtt.NON_RETAIN)
            end
         end
      end

      if (serialNumber == "WB") then
         if (resourcePath == "action/0/buzzer") then
            if (value == "on") then
               mqtt.wb:publish("/devices/buzzer/controls/enabled/on", 1, mqtt.QOS_0, mqtt.NON_RETAIN)
            elseif (value == "off") then
               mqtt.wb:publish("/devices/buzzer/controls/enabled/on", 0, mqtt.QOS_0, mqtt.NON_RETAIN)
            end
         end
      end

   end
end


local function http_server_data_handler(req)
   local type_item = req:param("item")
   local return_object
   local impact_data_object, i = {}, 0
   local table = ReverseTable(impact_reports.index.serialNumber:select({type_item}, {limit = 30000, iterator = 'REQ'}))
   for _, tuple in pairs(table) do
      local serialNumber = tuple[4]
      i = i + 1
      impact_data_object[i] = {}
      impact_data_object[i].date = os.date("%Y-%m-%d, %H:%M:%S", tuple[2])
      impact_data_object[i][serialNumber] = tuple[6]
   end
   return_object = req:render{ json = impact_data_object }
   return return_object
end

local function http_server_data_dashboard_handler(req)
      local return_object
      local impact_data_object, i = {}, 0

      for _, tuple in impact_reports.index.secondary:pairs(nil, { iterator = box.index.REQ}) do
         i = i + 1
         impact_data_object[i] = {}
         impact_data_object[i].timestamp = tuple[2]
         impact_data_object[i].subscriptionId = tuple[3]
         impact_data_object[i].serialNumber = tuple[4]
         impact_data_object[i].resourcePath = tuple[5]
         impact_data_object[i].value = tuple[6]
         if i > 100 then break end
      end

      if (i > 0) then
         return_object = req:render{ json =  impact_data_object  }
      else
         return_object = req:render{ json = { none_data = "true" } }
      end

      return return_object
end


local function http_server_action_handler(req)
   local action_param = req:param("action")
   local result
   if (action_param ~= nil) then
      if (action_param == "on_light_1") then
         result = mqtt.wb:publish("/devices/noolite_tx_0x290/controls/state/on", "1", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "off_light_1") then
         result = mqtt.wb:publish("/devices/noolite_tx_0x290/controls/state/on", "0", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "on_light_2") then
         result = mqtt.wb:publish("/devices/noolite_tx_0x291/controls/state/on", "1", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "off_light_2") then
         result = mqtt.wb:publish("/devices/noolite_tx_0x291/controls/state/on", "0", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "on_ac") then
         result = mqtt.wb:publish("/devices/wb-mr6c_105/controls/K4/on", "1", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "off_ac") then
         result = mqtt.wb:publish("/devices/wb-mr6c_105/controls/K4/on", "0", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "on_fan") then
         result = mqtt.wb:publish("/devices/wb-mr6c_105/controls/K5/on", "1", mqtt.QOS_1, mqtt.NON_RETAIN)
      elseif (action_param == "off_fan") then
         result = mqtt.wb:publish("/devices/wb-mr6c_105/controls/K5/on", "0", mqtt.QOS_1, mqtt.NON_RETAIN)
      end
      print(result, action_param)
      return req:render{ json = { result = result } }
   end
end

local function http_server_root_handler(req)
   return req:redirect_to('/dashboard')
end

local function http_server_html_handler(req)
   local proto_menu, menu = {
                        {href = "/dashboard", name="Dashboard"},
                        --{href = "/dashboard-graph", name="Graph"},
                        {href = "/internal-temperature", name="Internal Temperature"},
                        {href = "/light", name="Light"},
                        --{href = "/weather", name="Weather"},
                        {href = "/water", name="Water"},
                        {href = "/power", name="Power"},
                        --{href = "/dashboard-subscriptions", name="Subscriptions"},
                        --{href = "/dashboard-settings", name="Settings"}
                     }, {}

   for i, item in pairs(proto_menu) do
      menu[i] = {}
      menu[i].href=item.href
      menu[i].name=item.name
      if (item.href == req.path) then
         menu[i].class="active"
      end
   end

   return req:render{ menu = menu }
end

local function mqtt_callback(message_id, topic, payload, gos, retain)
   --print(message_id, topic, payload, gos, retain)
   local _, _, sensor_topic, sensor_address = string.find(topic, "(/devices/.+/controls/)(.+)$")
   if (sensor_address ~= nil) then
      local value = tonumber(payload)
      local timestamp = os.time()
      local resourcePath = sensor_topic
      local serialNumber = sensor_address
      local subscriptionId = "internal-mqtt"
      impact_reports:insert{nil, timestamp, subscriptionId, serialNumber, resourcePath, value}
      --print(timestamp, serialNumber, resourcePath, value)
   end

   local _, _, vaisala_sensor_topic = string.find(topic, "(/devices/vaisala/data)")
   if (vaisala_sensor_topic ~= nil and payload ~= nil) then
      local vaisala_data = {}
      _, _, vaisala_data.STATa, vaisala_data.Ta, vaisala_data.RHa, vaisala_data.PAa, vaisala_data.NO2, vaisala_data.SO2, vaisala_data.CO, vaisala_data.H2S, vaisala_data.PM25, vaisala_data.PM10, vaisala_data.STATw, vaisala_data.WD, vaisala_data.WDMAX, vaisala_data.WDMIN, vaisala_data.WS, vaisala_data.WSMAX, vaisala_data.WSMIN, vaisala_data.Tw, vaisala_data.RHw, vaisala_data.PAw, vaisala_data.Ha, vaisala_data.Hd, vaisala_data.Hi, vaisala_data.Ra_mm, vaisala_data.Ra_s, vaisala_data.Ra_mmh  = string.find(payload, "STATa=(%d+%.?%d*), Ta=(%d+%.?%d*)oC, RHa=(%d+%.?%d*)%%, PAa=(%d+%.?%d*)mbar, NO2=(%d+%.?%d*).g/m3, SO2=(%d+%.?%d*).g/m3, CO=(%d+%.?%d*).g/m3, H2S=(%d+%.?%d*).g/m3, PM2.5=(%d+%.?%d*).g/m3, PM10=(%d+%.?%d*).g/m3, STATw=(%d+%.?%d*), WD=(%d+)dir, WDMAX=(%d+)dir, WDMIN=(%d+)dir, WS=(%d+%.?%d*)m/s, WSMAX=(%d+%.?%d*)m/s, WSMIN=(%d+%.?%d*)m/s, Tw=(%d+%.?%d*)oC, RHw=(%d+%.?%d*)%%, PAw=(%d+%.?%d*)mm Hg, Ha=(%d+%.?%d*)mm , Hd=(%d+%.?%d*)s , Hi=(%d+%.?%d*)mm/h, Ra=(%d+%.?%d*)mm, Ra=(%d+%.?%d*)s, Ra=(%d+%.?%d*)mm/h")

      local timestamp = os.time()
      local resourcePath = "/devices/vaisala/data"
      local subscriptionId = "internal-vaisala"
      for value_name, value_data in pairs(vaisala_data) do
         local value = tonumber(value_data)
         local serialNumber = value_name
         impact_reports:insert{nil, timestamp, subscriptionId, serialNumber, resourcePath, value}
         --print(timestamp, serialNumber, resourcePath, value)
      end

   end
end


box.cfg { listen = 3313, log_level = 4, memtx_dir = "./db", vinyl_dir = "./db", wal_dir = "./db"  }
box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})

impact_reports = box.schema.space.create('impact_reports', {if_not_exists = true, engine = 'vinyl'})
box.schema.sequence.create("impact_reports_sequence", {if_not_exists = true})
impact_reports:create_index('primary', {sequence="impact_reports_sequence", if_not_exists = true})
impact_reports:create_index('secondary', {type = 'tree', unique = false, parts = {2, 'unsigned', 4, 'string'}, if_not_exists = true })
impact_reports:create_index('serialNumber', {type = 'tree', unique = false, parts = {4, 'string'}, if_not_exists = true })

settings = box.schema.space.create('settings', {if_not_exists = true, engine = 'vinyl'})
settings:create_index('key', { parts = {1, 'string'}, if_not_exists = true })


mqtt.wb = mqtt.new(config.MQTT_WIRENBOARD_ID, true)
local mqtt_ok, mqtt_err = mqtt.wb:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
if (mqtt_ok ~= true) then
   print ("Error mqtt: "..(mqtt_err or "No error"))
   os.exit()
end

mqtt.wb:on_message(mqtt_callback)
mqtt.wb:subscribe('/devices/wb-w1/controls/+', 0)

mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Urms L1', 0)

mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Frequency', 0)

mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L1', 0) --общее
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L2', 0) --внутреннее питание
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 P L3', 0) --розетка
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 Total P', 0) --суммарное

mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L1', 0) --общее
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L2', 0) --внутреннее питание
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 Irms L3', 0) --розетка

mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L1', 0) --общее
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L2', 0) --внутреннее питание
mqtt.wb:subscribe('/devices/wb-map12h_156/controls/Ch 1 AP energy L3', 0) --розетка

mqtt.wb:subscribe('/devices/wb-mr6c_105/controls/Input 0 counter', 0)
mqtt.wb:subscribe('/devices/wb-adc/controls/Vin', 0)
mqtt.wb:subscribe('/devices/system/controls/Current uptime', 0)

mqtt.wb:subscribe('/devices/vaisala/data', 0)

http_server:route({ path = '/data_dashboard' }, http_server_data_dashboard_handler)
http_server:route({ path = '/data' }, http_server_data_handler)
http_server:route({ path = '/action' }, http_server_action_handler)

http_server:route({ path = '/' }, http_server_root_handler)
http_server:route({ path = '/dashboard', file = 'dashboard.html' }, http_server_html_handler)
http_server:route({ path = '/internal-temperature', file = 'dashboard-temperature.html' }, http_server_html_handler)
http_server:route({ path = '/power', file = 'power.html' }, http_server_html_handler)
http_server:route({ path = '/water', file = 'water.html' }, http_server_html_handler)
http_server:route({ path = '/weather', file = 'weather.html' }, http_server_html_handler)
http_server:route({ path = '/light', file = 'light.html' }, http_server_html_handler)


--local table = impact_reports.index.serialNumber:select({'Ch 1 P L1'}, {limit = 5, iterator = 'REQ'})
--print(inspect(table))


--os.exit()



http_server:start()