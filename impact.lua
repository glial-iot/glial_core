#!/usr/bin/env tarantool
local json = require 'json'
local base64 = require 'base64'
local config = require 'config'

local http_client = require('http.client')

local impact = {}


function impact.create_mqtt_token(username, password, tenant, description)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {description = description, groupName = tenant, username = username}
   local url = config.IMPACT_URL..'/m2m/token/mqtt'
   local r = http_client.put(url, json.encode(data), { headers = headers })
   return r.body
end

function impact.get_tokens(username, password, tenant)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/token?groupName='..tenant
   local r = http_client.get(url, { headers = headers_table })
   return r.body
end

function impact.delete_token(username, password, tenant, token)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/token?groupName='..tenant..'&token='..token
   local r = http_client.delete(url, { headers = headers_table })
   return r.body
end



function impact.get_my_subscriptions(username, password)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/mysubscriptions'
   local r = http_client.get(url, { headers = headers_table })
   return r.body
end

function impact.delete_subscription(username, password, subscription_id)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local url = config.IMPACT_URL..'/m2m/subscriptions/'..subscription_id
   local r = http_client.delete(url, { headers = headers_table })
   return r.body
end

function impact.new_subscription(username, password, tenant, subscription_topic)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers_table = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {deletionPolicy = 0, groupName = tenant, subscriptionType = "resources", resources = {{resourcePath = subscription_topic}}}
   local url = config.IMPACT_URL..'/m2m/subscriptions?type=resources'
   local r = http_client.post(url, json.encode(data), { headers = headers_table })
   return r.body
end



function impact.set_rest_callback(username, password, callback_url)
   local basic = "Basic "..(base64.to_base64(username..":"..password))
   local headers = { ['Content-Type'] = 'application/json', ['Accept'] = 'application/json', ['Authorization'] = basic}
   local data = {headers = {}, url = callback_url}
   local url = config.IMPACT_URL..'/m2m/applications/registration'
   local r = http_client.put(url, json.encode(data), { headers = headers })
   return r.body
end


return impact


