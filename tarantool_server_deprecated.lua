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

local function impact_rest_http_catcher(req)
   local body = req:read({delimiter = nil, chunk = 1000}, 10)
   local status, json_decoded_data = pcall(json.decode, body)
   if (status == true and json_decoded_data ~= nil) then
      impact_rest_handler(json_decoded_data)
   end
   return { status = 200 }
end


local function http_server_data_handler(req)
      local return_object
      local impact_data_object, i = {}, 0

      for _, tuple in impact_reports.index.timestamp:pairs(nil, { iterator = box.index.REQ}) do
         i = i + 1
         impact_data_object[i] = {}
         impact_data_object[i].timestamp = tuple[2]
         impact_data_object[i].subscriptionId = tuple[3]
         impact_data_object[i].serialNumber = tuple[4]
         impact_data_object[i].resourcePath = tuple[5]
         impact_data_object[i].value = tuple[6]
      end

      if (i > 0) then
         return_object = req:render{ json = { impact_data_object } }
      else
         return_object = req:render{ json = { none_data = "true" } }
      end

      return return_object
end

local function http_server_action_handler(req)
   local type_param = req:param("type")

   if (type_param ~= nil) then
      if (type_param == "mqtt_send") then
         local value_param, topic_param = req:param("value"), req:param("topic")
         if (value_param == nil or topic_param == nil) then return nil end
         local ok, err = mqtt.impact:publish(config.MQTT_IMPACT_TOKEN.."/"..topic_param, value_param, mqtt.QOS_0, mqtt.NON_RETAIN)
         if ok then
            print(ok, err)
         end
         return req:render{ json = { mqtt_result = ok } }
      end
      if (type_param == "get_token") then
         --local answer = impact.create_mqtt_token("test_user", "test_pass1", "test_tenant", "test_token2")
         local answer = impact.get_tokens("test_user", "test_pass1", "test_tenant")

         local return_object = req:render{ json = { data = answer } }
         return return_object
      end
      if (type_param == "register_callback") then
         print("register_callback")
      end
      if (type_param == "settings_login") then
         print("settings_login")

      end
      if (type_param == "get_my_subscriptions") then
         local answer = impact.get_my_subscriptions("test_user", "test_pass1")
         --local return_object = req:render{ json = { data = answer } }
         return {status = 200, body = answer}
      end

      if (type_param == "delete_subscription") then
         local answer = impact.delete_subscription("test_user", "test_pass1", req:param("subscription_id"))
         return {status = 200, body = answer}
      end
      if (type_param == "new_subscription") then
         local answer = impact.new_subscription("test_user", "test_pass1", "test_tenant", req:param("subscription_topic"))
         return {status = 200, body = answer}
      end
      return nil
   end

end

local function http_server_root_handler(req)
   return req:redirect_to('/dashboard')
end

local function set_callback()
   fiber.sleep(1)
   local ngrock_url_api = 'http://127.0.0.1:4040/api/tunnels'
   local r = http_client.get(ngrock_url_api)
   local data = json.decode(r.body)
   local url = data.tunnels[1].public_url.."/impact_rest_endpoint"
   print("local url: "..url, impact.set_rest_callback("test_user", "test_pass1", url))
end
fiber.create(set_callback)

mqtt.impact = mqtt.new(config.MQTT_IMPACT_ID, true)
mqtt.impact:login_set(config.MQTT_IMPACT_LOGIN, config.MQTT_IMPACT_PASSWORD)
local mqtt_ok, mqtt_err = mqtt.impact:connect({host=config.MQTT_IMPACT_HOST,port=config.MQTT_IMPACT_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
if (mqtt_ok ~= true) then
   print ("Error mqtt: "..(mqtt_err or "No error"))
   os.exit()
end

mqtt.wb = mqtt.new(config.MQTT_WIRENBOARD_ID, true)
mqtt_ok, mqtt_err = mqtt.wb:connect({host=config.MQTT_WIRENBOARD_HOST,port=config.MQTT_WIRENBOARD_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
if (mqtt_ok ~= true) then
   print ("Error mqtt: "..(mqtt_err or "No error"))
   os.exit()
end


http_server:route({ path = '/impact_rest_endpoint' }, impact_rest_http_catcher)
http_server:route({ path = '/data' }, http_server_data_handler)
http_server:route({ path = '/action' }, http_server_action_handler)

http_server:route({ path = '/' }, http_server_root_handler)
http_server:route({ path = '/dashboard', file = 'dashboard.html' })
http_server:route({ path = '/dashboard-subscriptions', file = 'dashboard-subscriptions.html' })
http_server:route({ path = '/dashboard-settings', file = 'dashboard-settings.html' })



box.cfg { listen = 3313, log_level = 4, memtx_dir = "./db/memtx", vinyl_dir = "./db/vinyl", wal_dir = "./db/wal"  }
box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})
impact_reports = box.schema.space.create('impact_reports', {if_not_exists = true, engine = 'vinyl'})
box.schema.sequence.create("impact_reports_sequence", {if_not_exists = true})
impact_reports:create_index('index', {sequence="impact_reports_sequence", if_not_exists = true})
impact_reports:create_index('timestamp', {type = 'tree', unique = false, parts = {2, 'unsigned'}, if_not_exists = true })

settings = box.schema.space.create('settings', {if_not_exists = true, engine = 'vinyl'})
settings:create_index('key', { parts = {1, 'string'}, if_not_exists = true })


-- settings:insert{"token","test_token"}
--print(inspect(settings.index.key:min{"test_token"}))



http_server:start()
