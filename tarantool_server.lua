#!/usr/bin/env tarantool
local mqtt = require 'mqtt'
local inspect = require 'inspect'
local json = require 'json'
local base64 = require 'base64'
local fiber = require 'fiber'
local box = box
local impact_reports, settings

local config = {}
config.MQTT_IMPACT_HOST = "impact.iot.nokia.com"
config.MQTT_IMPACT_PORT = 1883
config.MQTT_IMPACT_LOGIN = "TEST_USER"
config.MQTT_IMPACT_PASSWORD = "0wYlg9KJ5E+ksmvt7l2mU6ucSSo/WjRDCdCgd2pQpF0="
config.MQTT_IMPACT_ID = "impact_tarantool_client"
config.MQTT_IMPACT_TOKEN = "trqspu69qcz7"

config.MQTT_WIRENBOARD_HOST = "192.168.1.59"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "tarantool_client"

config.HTTP_PORT = 8080

config.IMPACT_URL = "https://impact.iot.nokia.com"
config.NOOLITE_URL = "http://192.168.1.222"

local http_client = require('http.client')
local http_server = require('http.server').new(nil, config.HTTP_PORT, {charset = "application/json"})

io.stdout:setvbuf("no")


local function create_mqtt_token(username, password, tenant, description)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {description = description, groupName = tenant, username = username}
   local url = config.IMPACT_URL..'/m2m/token/mqtt'
   local r = http_client.put(url, json.encode(data), { headers = headers })
   return r.body
end

local function get_tokens(username, password, tenant)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/token?groupName='..tenant
   local r = http_client.get(url, { headers = headers_table })
   return r.body
end

local function delete_token(username, password, tenant, token)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/token?groupName='..tenant..'&token='..token
   local r = http_client.delete(url, { headers = headers_table })
   return r.body
end



local function get_my_subscriptions(username, password)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/mysubscriptions'
   local r = http_client.get(url, { headers = headers_table })
   return r.body
end

local function delete_subscription(username, password, subscription_id)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/subscriptions/'..subscription_id
   local r = http_client.delete(url, { headers = headers_table })
   return r.body
end

local function new_subscription(username, password, tenant, subscription_topic)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {deletionPolicy = 0, groupName = tenant, subscriptionType = "resources", resources = {{resourcePath = subscription_topic}}}
   local url = config.IMPACT_URL..'/m2m/subscriptions?type=resources'
   print(json.encode(data))
   local r = http_client.post(url, json.encode(data), { headers = headers_table })
   return r.body
end









local function set_rest_callback(username, password, callback_url)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {headers = {}, url = callback_url}
   local url = config.IMPACT_URL..'/m2m/applications/registration'
   local r = http_client.put(url, json.encode(data), { headers = headers })
   return r.body
end




local function noolite_action(command, channel)
   if command == "on" then command = 2
   elseif command == "off" then command = 0
   elseif command == "toggle" then command = 4
   end

   local url = config.NOOLITE_URL..'/api.htm?ch='..channel..'&cmd='..command
   local r = http_client.get(url)
   return r.body
end


local function impact_rest_handler(json_data)
   for i = 1, #json_data.reports do
      local subscriptionId = json_data.reports[i].subscriptionId
      local serialNumber = json_data.reports[i].serialNumber
      local resourcePath = json_data.reports[i].resourcePath
      local value = json_data.reports[i].value
      local timestamp = json_data.reports[i].timestamp

      impact_reports:insert{nil, timestamp, subscriptionId, serialNumber, resourcePath, value}

      if (serialNumber == "NOOLITE_SK_0" or serialNumber == "NOOLITE_SK_1") then
         if (resourcePath == "action/0/light") then
            if (value == "on" or value == "off" or value == "toggle") then
               if (serialNumber == "NOOLITE_SK_0") then
                  noolite_action(value, 0)
               elseif (serialNumber == "NOOLITE_SK_1") then
                  noolite_action(value, 1)
               end
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
      local tarantool_data = box.space.impact_reports:select{}

      if (#tarantool_data > 0) then
         local impact_data_object = {}
         for i = 1, #tarantool_data do
            impact_data_object[i] = {}
            impact_data_object[i].resourcePath = tarantool_data[i][5]
            impact_data_object[i].serialNumber = tarantool_data[i][4]
            impact_data_object[i].subscriptionId = tarantool_data[i][3]
            impact_data_object[i].timestamp = tarantool_data[i][2]
            impact_data_object[i].value = tarantool_data[i][6]
         end
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
         --local answer = create_mqtt_token("test_user", "test_pass1", "test_tenant", "test_token2")
         local answer = get_tokens("test_user", "test_pass1", "test_tenant")

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
         local answer = get_my_subscriptions("test_user", "test_pass1")
         --local return_object = req:render{ json = { data = answer } }
         return {status = 200, body = answer}
      end

      if (type_param == "delete_subscription") then
         local answer = delete_subscription("test_user", "test_pass1", req:param("subscription_id"))
         return {status = 200, body = answer}
      end
      if (type_param == "new_subscription") then
         local answer = new_subscription("test_user", "test_pass1", "test_tenant", req:param("subscription_topic"))
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
   print("local url: "..url)
   print(set_rest_callback("test_user", "test_pass1", url))
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



box.cfg { listen = 3313 }

if (box.space.impact_reports == nil) then
   impact_reports = box.schema.space.create('impact_reports')
   box.schema.sequence.create("impact_reports_sequence")
   impact_reports:create_index('index', {sequence="impact_reports_sequence"})
   impact_reports:create_index('timestamp', {type = 'tree', unique = false, parts = {2, 'unsigned'} })

   settings = box.schema.space.create('settings')
   settings:create_index('key', { parts = {1, 'string'} })

   box.schema.user.grant('guest', 'read,write,execute', 'universe')
else
   impact_reports = box.space.impact_reports
   settings = box.space.settings
end

--http_server_data_handler()

--print(inspect(impact_reports.index.timestamp:min{100}))
-- settings:insert{"token","test_token"}
--print(inspect(settings.index.key:min{"test_token"}))



http_server:start()
