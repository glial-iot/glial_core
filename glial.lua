#!/usr/bin/env tarantool
local inspect = require 'libs/inspect'
local box = box

local scripts = require 'scripts'

local http_system = require 'http_system'
local scripts_drivers = require 'scripts_drivers' --TODO: переименовать в соотвествии с официальной семантикой
local scripts_webevents = require 'scripts_webevents'
local scripts_busevents = require 'scripts_busevents'
local scripts_timerevents = require 'scripts_timerevents'
local scripts_sheduleevents = require 'scripts_sheduleevents'

local bus = require 'bus'
local system = require "system"
local logger = require "logger"
local config = require 'config'
local backup_restore = require 'backup_restore'
local settings = require 'settings'

local function start()
   local tarantool_bin_port = tonumber(os.getenv('TARANTOOL_BIN_PORT'))
   local glial_http_port = tonumber(os.getenv('HTTP_PORT')) or config.HTTP_PORT
   local tarantool_wal_dir = os.getenv('TARANTOOL_WAL_DIR') or config.dir.DATABASE
   local log_type = os.getenv('LOG_TYPE') or "PIPE"
   local log_point
   if (log_type ~= "NONE") then
      log_point = "pipe: PORT="..glial_http_port.."./http_pipe_logger.lua"
   end

   system.dir_check(tarantool_wal_dir)
   system.dir_check(config.dir.BACKUP)
   system.dir_check(config.dir.DUMP_FILES)

   box.cfg {
      hot_standby = true,
      listen = tarantool_bin_port,
      log_level = 4,
      memtx_dir = tarantool_wal_dir,
      vinyl_dir = tarantool_wal_dir,
      wal_dir = tarantool_wal_dir,
      log = log_point
   }

   if (tarantool_bin_port ~= nil) then
      print("Tarantool server runned on "..tarantool_bin_port.." port")
   end

   box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})

   logger.storage_init()
   local msg_reboot = "GLIAL, "..system.version()..", tarantool "..require('tarantool').version
   logger.add_entry(logger.REBOOT, "------------", msg_reboot, nil, "Tarantool pid "..require('tarantool').pid())

   http_system.init(glial_http_port)
   logger.http_init()
   logger.add_entry(logger.INFO, "System", "HTTP subsystem initialized")

   require('system_webevent').init()

   settings.init()
   logger.add_entry(logger.INFO, "System", "Settings database initialized")

   bus.init()
   logger.add_entry(logger.INFO, "System", "Bus and FIFO worker initialized")

   logger.add_entry(logger.INFO, "System", "Starting script subsystem...")
   scripts.init()

   if (tonumber(os.getenv('SAFEMODE')) == 1 and tonumber(os.getenv('TARANTOOL_CONSOLE')) ~= 1) then
      scripts.safe_mode_error_all()
   else
      logger.add_entry(logger.INFO, "System", "Starting web-events...")
      scripts_webevents.init()

      logger.add_entry(logger.INFO, "System", "Starting bus-events...")
      scripts_busevents.init()

      logger.add_entry(logger.INFO, "System", "Starting timer-events...")
      scripts_timerevents.init()

      logger.add_entry(logger.INFO, "System", "Starting shedule-events...")
      scripts_sheduleevents.init()

      logger.add_entry(logger.INFO, "System", "Starting drivers...")
      scripts_drivers.init()
   end


   backup_restore.init()
   backup_restore.create_backup("Backup after start")
   logger.add_entry(logger.INFO, "System", "Backup created")
   backup_restore.remove_old_files()

   logger.add_entry(logger.INFO, "System", "System started")

   if (tonumber(os.getenv('TARANTOOL_CONSOLE')) == 1) then
      logger.add_entry(logger.INFO, "System", "Console active")
      if pcall(require('console').start) then
         os.exit(0)
      end
   end
end


return {start = start}
