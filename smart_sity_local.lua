#!/usr/bin/env tarantool
local inspect = require 'inspect'
local json = require 'json'
local fiber = require 'fiber'
local impact = require 'impact'
local log = require 'log'
local box = box

local proto_menu = {}

local http_system = require 'http_system'

local scripts_drivers = require 'scripts_drivers'
local scripts_events = require 'scripts_events'
local ts_storage = require 'ts_storage'
local bus = require 'bus'
local system = require "system"
local logger = require "logger"

io.stdout:setvbuf("no")

local function http_server_data_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local table = system.reverse_table(ts_storage.object.index.serial_number:select({type_item}, {iterator = 'REQ'}))
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      i = i + 1
      data_object[i] = {}
      data_object[i].date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      data_object[i][serialNumber] = tuple[4]
      if (type_limit ~= nil and type_limit <= i) then break end
   end
   return_object = req:render{ json = data_object }
   return return_object
end


local function http_server_data_temperature_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local table = system.reverse_table(ts_storage.object.index.primary:select(nil, {iterator = 'REQ'}))
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      if (type_item == "local") then
         if (serialNumber == "28-000008e7f176" or serialNumber == "28-000008e538e6") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(tuple[4])
         end
      end
      if (type_limit ~= nil and type_limit <= i) then break end
   end
   return_object = req:render{ json = data_object }
   return return_object
end


local function http_server_data_power_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0
   local raw_table = ts_storage.object.index.primary:select(nil, {iterator = 'REQ'})
   local table = system.reverse_table(raw_table)
   for _, tuple in pairs(table) do
      local serialNumber = tuple[5]
      local date = os.date("%Y-%m-%d, %H:%M:%S", tuple[3])
      if (type_item == "I") then
         if (serialNumber == "Ch 1 Irms L1" or serialNumber == "Ch 1 Irms L2" or serialNumber == "Ch 1 Irms L3") then
            i = i + 1
            data_object[i] = {}
            data_object[i].date = date
            data_object[i][serialNumber] = tonumber(tuple[4])
         end
         if (type_limit ~= nil and type_limit <= i) then break end
      end
   end
   return_object = req:render{ json = data_object }
   return return_object
end


local function http_server_data_tsstorage_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0

   for _, tuple in ts_storage.object.index.primary:pairs(nil, { iterator = box.index.REQ}) do
      i = i + 1
      data_object[i] = {}
      data_object[i].timestamp = tuple[3]
      data_object[i].subscriptionId = "none"
      data_object[i].serialNumber = tuple[5]
      data_object[i].resourcePath = tuple[2]
      data_object[i].value = tuple[4]
      if (type_limit ~= nil and type_limit <= i) then break end
   end
--
   if (i > 0) then
      return_object = req:render{ json =  data_object  }
   else
      return_object = req:render{ json = { none_data = "true" } }
   end

   return return_object
end

local function http_server_data_bus_storage_handler(req)
   local type_item, type_limit = req:param("item"), tonumber(req:param("limit"))
   local return_object
   local data_object, i = {}, 0

   for _, tuple in bus.bus_storage.index.topic:pairs() do
      i = i + 1
      data_object[i] = {}
      data_object[i].topic = tuple[1]
      data_object[i].timestamp = tuple[2]
      data_object[i].value = tuple[3]
      if (type_limit ~= nil and type_limit <= i) then break end
      --print(tuple[1], tuple[2], tuple[3])
   end

   if (i > 0) then
      return_object = req:render{ json =  data_object  }
   else
      return_object = req:render{ json = { none_data = "true" } }
   end

   return return_object
end



local function http_server_root_handler(req)
   return req:redirect_to('/dashboard')
end

local function http_server_html_handler(req)
   local menu = {}
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

local function box_config()
   box.cfg { listen = 3313, log_level = 4, memtx_dir = "./db", vinyl_dir = "./db", wal_dir = "./db", log = "pipe: ./http_pipe_logger.lua" }
   box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})
end


local function database_init()
   --settings = box.schema.space.create('settings', {if_not_exists = true, engine = 'vinyl'})
   --settings:create_index('key', { parts = {1, 'string'}, if_not_exists = true })
end

local function endpoints_list()
   local endpoints = {}
   endpoints[#endpoints+1] = {"/", nil, nil, http_server_root_handler}
   endpoints[#endpoints+1] = {"/dashboard", "dashboard.html", "Dashboard", http_server_html_handler}
   endpoints[#endpoints+1] = {"/data", nil, nil, http_server_data_handler}

   endpoints[#endpoints+1] = {"/logger", "logger.html", "Logs", http_server_html_handler}
   endpoints[#endpoints+1] = {"/logger-data", nil, nil, logger.return_all_entry}

   endpoints[#endpoints+1] = {"/bus_storage", "bus_storage.html", "Bus storage", http_server_html_handler}
   endpoints[#endpoints+1] = {"/bus_storage-data", nil, nil, http_server_data_bus_storage_handler}

   endpoints[#endpoints+1] = {"/tsstorage", "tsstorage.html", "TS Storage", http_server_html_handler}
   endpoints[#endpoints+1] = {"/tsstorage-data", nil, nil, http_server_data_tsstorage_handler}

   endpoints[#endpoints+1] = {"/temperature", "temperature.html", "Temperature", http_server_html_handler}
   endpoints[#endpoints+1] = {"/temperature-data", nil, nil, http_server_data_temperature_handler}

   endpoints[#endpoints+1] = {"/power", "power.html", "Power", http_server_html_handler}
   endpoints[#endpoints+1] = {"/power-data", nil, nil, http_server_data_power_handler}

   endpoints[#endpoints+1] = {"/vaisala", "vaisala.html", "Vaisala", http_server_html_handler}

   endpoints[#endpoints+1] = {"/water", "water.html", "Water", http_server_html_handler}
   endpoints[#endpoints+1] = {"/control", "control.html", "Control", http_server_html_handler}

   endpoints[#endpoints+1] = {"/tarantool", "tarantool.html", "Tarantool", http_server_html_handler}

   endpoints[#endpoints+1] = {"/#", nil, "———————", nil}
   endpoints[#endpoints+1] = {"http://192.168.1.111/", nil, "⨠ WirenBoard", nil}
   endpoints[#endpoints+1] = {"http://192.168.1.45:9000/", nil, "⨠ Portainer", nil}
   endpoints[#endpoints+1] = {"/#", nil, "———————", nil}
   endpoints[#endpoints+1] = {"http://a.linergo.ru/login.xhtml", nil, "⨠ Linergo", nil}
   endpoints[#endpoints+1] = {"http://gascloud.ru/", nil, "⨠ GasCloud", nil}
   endpoints[#endpoints+1] = {"http://unilight.su/", nil, "⨠ Unilight", nil}
   endpoints[#endpoints+1] = {"https://www.m2mconnect.ru/Account/Login", nil, "⨠ M2M Connect", nil}
   return endpoints
end


local function events_action_config() -- перенести в events
   for name, item in pairs(scripts_events) do
      if (item ~= nil and item.type ~= nil and item.type == scripts_events.types.HTTP and item.endpoint ~= nil) then
         http_server:route({ path = item.endpoint, file = item.file_endpoint }, item.event_function)
         logger.add_entry(logger.INFO, "Events subsystem", 'Event "'..item.name..'" bind endpoint "'..item.endpoint..'"')
      end
   end
end


local function fifo_storage_worker()
   while true do
      local key, topic, timestamp, value = bus.get_delete_value()
      if (key ~= nil) then
         bus.bus_storage:upsert({topic, timestamp, value}, {{"=", 2, timestamp} , {"=", 3, value}})
         local _, _, new_topic, name = string.find(topic, "(/.+/)(.+)$")
         if (topic ~= nil and name ~= nil) then
            ts_storage.update_value(topic, value, name)
         end
         --fiber.sleep(0.001)
      else
         fiber.sleep(0.01)
      end
   end
end


box_config()

logger.init()
logger.add_entry(logger.INFO, "Main system", "System starts up...")

--database_init()
bus.init()
fiber.create(fifo_storage_worker)

logger.add_entry(logger.INFO, "Main system", "Common bus and FIFO worker initialized")
ts_storage.init()
logger.add_entry(logger.INFO, "Main system", "Time Series storage initialized")

logger.add_entry(logger.INFO, "Main system", "Events configured")
events_action_config()
http_system.init_server()
http_system.init_client()
proto_menu = http_system.enpoints_menu_config(endpoints_list())

scripts_drivers.start()
logger.add_entry(logger.INFO, "Main system", "Drivers started")

logger.add_entry(logger.INFO, "Main system", "System started")
