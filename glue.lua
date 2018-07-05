#!/usr/bin/env tarantool
local inspect = require 'libs/inspect'
local box = box

local scripts = require 'scripts'

local http_system = require 'http_system'
local scripts_drivers = require 'scripts_drivers'
local scripts_webevents = require 'scripts_webevents'
local system_webevent = require 'system_webevent'
local bus = require 'bus'
local system = require "system"
local logger = require "logger"
local config = require 'config'
local backup_restore = require 'backup_restore'


local function box_config()
   box.cfg { listen = 3313, log_level = 4, memtx_dir = config.dir.DATABASE, vinyl_dir = config.dir.DATABASE, wal_dir = config.dir.DATABASE, log = "pipe: ./http_pipe_logger.lua" }
   box.schema.user.grant('guest', 'read,write,execute', 'universe', nil, {if_not_exists = true})
end


system.dir_check(config.dir.DATABASE)
box_config()

logger.storage_init()
logger.add_entry(logger.INFO, "------------", "-----------------------------------------------------------------------")
logger.add_entry(logger.INFO, "System", "GLUE System, "..system.git_version()..", tarantool version "..require('tarantool').version..", pid "..require('tarantool').pid())

http_system.init()
logger.http_init()
logger.add_entry(logger.INFO, "System", "HTTP subsystem initialized")

system_webevent.init()

bus.init()
logger.add_entry(logger.INFO, "System", "Common bus and FIFO worker initialized")

logger.add_entry(logger.INFO, "System", "Starting script system...")
scripts.init()

--logger.add_entry(logger.INFO, "Main system", "Configuring web-events...")
--scripts_webevents.init()

logger.add_entry(logger.INFO, "System", "Starting drivers...")
scripts_drivers.init()

backup_restore.create_backup()
logger.add_entry(logger.INFO, "System", "Backup created")
backup_restore.remove_old_files()

logger.add_entry(logger.INFO, "System", "System started")

if tonumber(os.getenv('TARANTOOL_CONSOLE')) == 1 then
   logger.add_entry(logger.INFO, "System", "Console active")
    if pcall(require('console').start) then
        os.exit(0)
    end
end
