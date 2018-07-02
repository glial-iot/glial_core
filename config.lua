#!/usr/bin/env tarantool
local config = {}


config.dir = {}
config.dir.DATABASE = "db"

config.dir.BACKUP = "backup"
config.dir.DUMP_FILES = "dump"
config.MAX_BACKUP_FILES = 100
config.HTTP_PORT = 8080


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



