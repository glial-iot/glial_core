# Примеры драйверов

## Пример драйвера, работающего через HTTP

Пример драйвера, который получает значения о качестве воздуха с сервера в JSON и отправляет в шину. Проверки на корректность данных и http-код ответа опущены.

```lua
local function get_values()
   local client = require'http.client'.new();
   local http_result = client:post('http://exapble.com/sensors/pm/last.php')
   local decoded_data = require('json').decode(http_result.body)

   set_value("/air/pm25", decoded_data.pm25)
   set_value("/air/pm10", decoded_data.pm10)
end

local function main_loop()
   while true do
      get_values()
      fiber.sleep(60*5)
   end
end

function init()
   store.fiber_object = fiber.create(main_loop)
end

function destroy()
   if (store.fiber_object:status() ~= "dead") then
      store.fiber_object:cancel()
   end
end
```

## Пример драйвера, работающего через MQTT с обратным распространением данных

Пример драйвера c MQTT и обратным распространением данных: при изменении значения топика "/ud/1674/lora/commands" в bus, будет отправлено сообщение в MQTT.

```lua
local mqtt_host = "mosquitto"
local mqtt_port = 1883
local mqtt_name = "glue_".._script_name.."_"..require('system').random_string()
local mqtt_object
topics = {"/ud/1674/lora/commands"}

local function driver_mqtt_callback(message_id, topic, payload, qos, retain)
   if (payload == nil) then return end
   local data = json.decode(payload)
   local lora_data = {}
   _, _, lora_data.serial, lora_data.device_type  = string.find(topic, "devices/lora/(.+)/(.+)")
   if (data == nil or data.data == nil or data.status == nil) then return end
   if (lora_data.serial == nil or lora_data.device_type == nil) then return end

   set_value("/ud/1674/lora/"..lora_data.serial.."/".."temperature/1", tonumber(data.data.s1))
   set_value("/ud/1674/lora/"..lora_data.serial.."/".."rssi", tonumber(data.status.rssi))
   set_value("/ud/1674/lora/"..lora_data.serial.."/".."battery", tonumber(data.status.battery))

end

function init()
   local conn = socket.tcp_connect(mqtt_host, mqtt_port, 2)
   if (conn ~= nil) then
      conn:close()
      mqtt_object = mqtt.new(mqtt_name, true)
      local mqtt_status, mqtt_err = mqtt_object:connect({host=mqtt_host, port=mqtt_port})
      if (mqtt_status ~= true) then
         error('MQTT error '..(mqtt_err or "unknown error"))
      else
         mqtt_object:on_message(driver_mqtt_callback)
         mqtt_object:subscribe('/devices/lora/#', 0)
      end
   else
      error('Connect to host '..mqtt_host..' failed')
   end
end

function topic_update_callback(value, topic)
   mqtt_object:publish('devices/lora/commands', value, mqtt.QOS_0, mqtt.RETAIN)
end

function destroy()
   return false
end
```
