#!/usr/bin/env tarantool
local config = {}


config.dir = {}
config.dir.DATABASE = "db"

config.dir.BACKUP = "backup"
config.dir.DUMP_FILES = "dump"
config.MAX_BACKUP_FILES = 200
config.BACKUP_PERIODIC_HOURS = 5
config.HTTP_PORT = 8080

config.id = {}
config.id.bus = 600
config.id.bus_fifo = 601
config.id.logs = 610
config.id.scripts = 620
config.id.worktime_scripts = 621
config.id.settings = 630

--[[
config.limit.value = 10
config.limit.name = "Limit"
config.limit.description = "Power limit"
config.limit.type = {}
config.limit.type.item = config.BUS_LINK
config.limit.type.type = config.INTEGER

config.limit.type.item = config.PRESETS
config.limit.type.values = {10, 20, 30}

config.limit.type.item = config.VARIABLE
config.limit.type.min = 10
config.limit.type.max = 30 ]]

return config



