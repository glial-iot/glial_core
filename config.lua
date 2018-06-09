#!/usr/bin/env tarantool
local config = {}


config.dir = {}
config.dir.USER = "user"
config.dir.TEMPLATES = "templates"
config.dir.DATABASE = "db"
config.dir.SYSTEM = "system_scripts"
config.dir.TIMER_SCRIPTS = config.dir.USER.."/".."timer_scripts"
config.dir.EVENT_SCRIPTS = config.dir.USER.."/".."events_scripts"
config.dir.WEBEVENT_SCRIPTS = config.dir.USER.."/".."webevents_scripts"
config.dir.SYSTEM_WEBEVENT_SCRIPTS = config.dir.SYSTEM.."/".."webevents_scripts"
config.dir.DRIVERS = config.dir.USER.."/".."drivers"
config.dir.USER_HTML = config.dir.USER.."/".."html"
config.dir.USER_MENU = config.dir.USER.."/".."menu"
config.dir.SYSTEM_HTML = config.dir.TEMPLATES.."/".."system"
config.dir.BACKUP = "backup"

config.MAX_BACKUP_FILES = 20
config.HTTP_PANEL_PORT = 8080


return config
