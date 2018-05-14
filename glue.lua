#!/usr/bin/env tarantool
local inspect = require 'inspect'
local json = require 'json'
local fiber = require 'fiber'
local impact = require 'impact'
local log = require 'log'
local box = box

local http_system = require 'http_system'
local scripts_drivers = require 'scripts_drivers'
local scripts_webevents = require 'scripts_webevents'
local ts_storage = require 'ts_storage'
local bus = require 'bus'
local system = require "system"
local logger = require "logger"
local webedit = require "webedit"

local function http_server_root_handler(req)
   return req:redirect_to('/dashboard')
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
   endpoints[#endpoints+1] = {"/dashboard", "dashboard.html", "Dashboard", http_system.page_handler, "fas fa-chart-area"}
   endpoints[#endpoints+1] = {"/temperature", "temperature.html", "Temperature", http_system.page_handler, "fas fa-chart-area"}
   endpoints[#endpoints+1] = {"/power", "power.html", "Power", http_system.page_handler, "fas fa-chart-area"}
   endpoints[#endpoints+1] = {"/vaisala", "vaisala.html", "Vaisala", http_system.page_handler, "fas fa-chart-area"}
   endpoints[#endpoints+1] = {"/water", "water.html", "Water", http_system.page_handler, "fas fa-chart-area"}
   endpoints[#endpoints+1] = {"/actions", "actions.html", "Actions", http_system.page_handler, "fas fa-sliders-h"}


   endpoints[#endpoints+1] = {"/#", nil, "———————", nil}

   endpoints[#endpoints+1] = {"/control", "control.html", "Control", http_system.page_handler, "fas fa-cogs"}
   endpoints[#endpoints+1] = {"/tarantool", "tarantool.html", "Tarantool", http_system.page_handler, "fas fa-chart-area"}

   endpoints[#endpoints+1] = {"/logger", "logger.html", "Logs", http_system.page_handler, "fas fa-stream"}
   endpoints[#endpoints+1] = {"/logger-data", nil, nil, logger.return_all_entry}
   endpoints[#endpoints+1] = {"/logger-ext", nil, nil, logger.tarantool_pipe_log_handler}
   endpoints[#endpoints+1] = {"/logger-action", nil, nil, logger.actions}

   endpoints[#endpoints+1] = {"/webedit_list", "webedit_list.html", "Scripts", http_system.page_handler, "fas fa-edit"}
   endpoints[#endpoints+1] = {"/webedit_edit", "webedit_edit.html", nil, http_system.page_handler, nil}
   endpoints[#endpoints+1] = {"/webedit", nil, nil, webedit.main}

   endpoints[#endpoints+1] = {"/bus_storage", "bus_storage.html", "Bus storage", http_system.page_handler, "fas fa-database"}
   endpoints[#endpoints+1] = {"/bus_storage-data", nil, nil, bus.http_handler}

   endpoints[#endpoints+1] = {"/#", nil, "———————", nil}

   endpoints[#endpoints+1] = {"http://192.168.1.111/", nil, "WirenBoard", nil, "fas fa-arrow-circle-right"}
   endpoints[#endpoints+1] = {"http://192.168.1.45:9000/", nil, "Portainer", nil, "fas fa-arrow-circle-right"}
   endpoints[#endpoints+1] = {"http://a.linergo.ru/login.xhtml", nil, 'Linergo', nil, "fas fa-external-link-alt"}
   endpoints[#endpoints+1] = {"http://gascloud.ru/", nil, "GasCloud", nil, "fas fa-external-link-alt"}
   endpoints[#endpoints+1] = {"http://unilight.su/", nil, "Unilight", nil, "fas fa-external-link-alt"}
   endpoints[#endpoints+1] = {"https://www.m2mconnect.ru/Account/Login", nil, "M2M Connect", nil, "fas fa-external-link-alt"}
   return endpoints
end

box_config()

logger.init()
logger.add_entry(logger.INFO, "Main system", "-----------------------------------------------------------------------")
logger.add_entry(logger.INFO, "Main system", "GLUE System, "..system.git_version()..", tarantool version "..require('tarantool').version..", pid "..require('tarantool').pid())

--database_init()
bus.init()
logger.add_entry(logger.INFO, "Main system", "Common bus and FIFO worker initialized")

ts_storage.init()
logger.add_entry(logger.INFO, "Main system", "Time Series storage initialized")

http_system.init_server()
http_system.init_client()
proto_menu = http_system.enpoints_menu_config(endpoints_list())
logger.add_entry(logger.INFO, "Main system", "HTTP subsystem initialized")

logger.add_entry(logger.INFO, "Main system", "Configuring web-events...")
scripts_webevents.init()

logger.add_entry(logger.INFO, "Main system", "Starting drivers...")
scripts_drivers.init()

logger.add_entry(logger.INFO, "Main system", "System started")
