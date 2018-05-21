#!/usr/bin/env tarantool
local inspect = require 'libs/inspect'
local json = require 'json'
local fiber = require 'fiber'
local log = require 'log'
local box = box

local http_system = require 'http_system'
local scripts_drivers = require 'scripts_drivers'
local scripts_webevents = require 'scripts_webevents'
local bus = require 'bus'
local system = require "system"
local logger = require "logger"
local webedit = require "webedit"
local config = require 'config'

local function http_server_root_handler(req)
   return req:redirect_to('/user_dashboard')
end

local function box_config()
   box.cfg { listen = 3313, log_level = 4, memtx_dir = "./db", vinyl_dir = "./db", wal_dir = "./db", log = "pipe: ./http_pipe_logger.lua" }
   box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})
end

local function system_menu_list()
   local m = {}

   m[#m+1] = {
      href = "/system_bus_storage",
      file = "system/bus_storage.html",
      name = "Bus storage",
      handler = http_system.generic_page_handler,
      icon = "fas fa-database"
   }

   m[#m+1] = {
      href = "/system_logger",
      file = "system/logger.html",
      name = "Logs",
      handler = http_system.generic_page_handler,
      icon = "fas fa-stream"
   }

   m[#m+1] = {
      href = "/system_webedit_list",
      file = "system/webedit_list.html",
      name = "Edit",
      handler = http_system.generic_page_handler,
      icon = "fas fa-edit"
   }

   m[#m+1] = {
      href = "/system_control",
      file = "system/control.html",
      name = "Control",
      handler = http_system.generic_page_handler,
      icon = "fas fa-cogs"
   }

   m[#m+1] = {
      href = "/system_tarantool",
      file = "system/tarantool.html",
      name = "Tarantool",
      handler = http_system.generic_page_handler,
      icon = "fas fa-chart-area"
   }

   m[#m+1] = {
      href = "/system_webedit_edit",
      file = "system/webedit_edit.html",
      name = nil,
      handler = http_system.generic_page_handler,
      icon = nil
   }

   m[#m+1] = {
      href = "/#",
      file = nil,
      name = "———————",
      handler = nil
   }
   return m
end

local function user_menu_file_init()
   local user_menu
   local current_func, error_msg = loadfile(config.USER_MENU_DIR.."/".."user_menu.lua")
   if (current_func == nil) then
      logger.add_entry(logger.ERROR, "User menu subsystem", 'Menu not load: "'..error_msg..'"')
   else
      user_menu = current_func() or {}
   end
   return user_menu
end

local function http_data_endpoints_init()
   http_system.endpoint_config("/", http_server_root_handler)
   http_system.endpoint_config("/system_logger_data", logger.return_all_entry)
   http_system.endpoint_config("/system_logger_ext", logger.tarantool_pipe_log_handler)
   http_system.endpoint_config("/system_logger_action", logger.actions)
   http_system.endpoint_config("/system_webedit_data", webedit.http_handler)
   http_system.endpoint_config("/system_bus_data", bus.http_data_handler)
   http_system.endpoint_config("/system_bus_action", bus.action_data_handler)
end

box_config()


logger.init()
logger.add_entry(logger.INFO, "Main system", "-----------------------------------------------------------------------")
logger.add_entry(logger.INFO, "Main system", "GLUE System, "..system.git_version()..", tarantool version "..require('tarantool').version..", pid "..require('tarantool').pid())

bus.init()
logger.add_entry(logger.INFO, "Main system", "Common bus and FIFO worker initialized")

webedit.init()

http_system.init_server()
http_system.init_client()
http_system.enpoints_menu_config(system_menu_list())
http_system.enpoints_menu_config(user_menu_file_init())
http_data_endpoints_init()
logger.add_entry(logger.INFO, "Main system", "HTTP subsystem initialized")

logger.add_entry(logger.INFO, "Main system", "Configuring web-events...")
scripts_webevents.init()

logger.add_entry(logger.INFO, "Main system", "Starting drivers...")
scripts_drivers.init()

logger.add_entry(logger.INFO, "Main system", "System started")
