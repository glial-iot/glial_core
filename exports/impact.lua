#!/usr/bin/env tarantool

local impact = {}

local box = box
local logger = require 'logger'
local settings = require 'settings'
local fiber = require 'fiber'
local mqtt = require 'mqtt'
local json = require 'json'
local base64 = require 'libs/base64'
local http_client = require('http.client')


impact.config = {}
impact.config.MQTT_HOST = "impact.iot.nokia.com"
impact.config.MQTT_PORT = 1883
impact.config.MQTT_LOGIN = "TEST_USER"
impact.config.MQTT_PASSWORD = "0wYlg9KJ5E+ksmvt7l2mU6ucSSo/WjRDCdCgd2pQpF0="
impact.config.MQTT_ID = "impact_tarantool_client"
impact.config.MQTT_TOKEN = "trqspu69qcz7"
impact.config.IMPACT_URL = "https://impact.iot.nokia.com"

impact.count = 0
impact.STATUS_SETTINGS_NAME = "impact_save"

function impact.create_mqtt_token(username, password, tenant, description)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {description = description, groupName = tenant, username = username}
   local url = impact.config.IMPACT_URL..'/m2m/token/mqtt'
   local r = http_client.put(url, json.encode(data), { headers = headers })
   return r.body
end

function impact.mqtt_init()
   impact.mqtt_conn = mqtt.new(impact.config.MQTT_ID, true)
   impact.mqtt_conn:login_set(impact.config.MQTT_LOGIN, impact.config.MQTT_PASSWORD)
   local mqtt_ok, mqtt_err = impact.mqtt_conn:connect({host=impact.config.MQTT_HOST,port=impact.config.MQTT_PORT,keepalive=60,log_mask=mqtt.LOG_ALL})
   if (mqtt_ok ~= true) then
      print ("Error impact-mqtt: "..(mqtt_err or "No error"))
   end
end

function impact.init()
   fiber.create(impact.rps_stat_worker)
   --impact.mqtt_init()
   --impact.create_mqtt_token(username, password, tenant, description)
end

function impact.get_status()
   local status, value = settings.get(impact.STATUS_SETTINGS_NAME, "false")
   if (value == "true") then value = true else value = false end
   return value
end

function impact.set_status(status)
   if (status == "false" or status == "true") then
      settings.set(impact.STATUS_SETTINGS_NAME, status)
   end
end

function impact.send_value(topic, value)
   local status, settings_value = settings.get(impact.STATUS_SETTINGS_NAME, "false")
   if (status == false or settings_value == "false") then return end
   impact.count = impact.count + 1
   if (topic == nil or value == nil) then return nil end
   if (impact.mqtt_conn == nil) then return nil end
   local ok, err = impact.mqtt_conn:publish(impact.config.MQTT_TOKEN.."/"..topic, value, mqtt.QOS_0, mqtt.NON_RETAIN)
   if ok then
      print(ok, err)
   end
end



function impact.rps_stat_worker()
   local bus = require 'bus'
   while true do
      bus.set_value("/glue/export/impact_count", impact.count)
      fiber.sleep(10)
   end
end



return impact

