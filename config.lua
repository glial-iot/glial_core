#!/usr/bin/env tarantool
local config = {}


config.dir = {}
config.dir.USER_DIR = "user"
config.dir.TEMPLATES_DIR = "templates"
config.dir.DATABASE_DIR = "db"
config.dir.SYSTEM_DIR = "system_scripts"
config.dir.TIMER_SCRIPTS_DIR = config.dir.USER_DIR.."/".."timer_scripts"
config.dir.EVENT_SCRIPTS_DIR = config.dir.USER_DIR.."/".."events_scripts"
config.dir.WEBEVENT_SCRIPTS_DIR = config.dir.USER_DIR.."/".."webevents_scripts"
config.dir.SYSTEM_WEBEVENT_SCRIPTS_DIR = config.dir.SYSTEM_DIR.."/".."webevents_scripts"
config.dir.DRIVERS_DIR = config.dir.USER_DIR.."/".."drivers"
config.dir.USER_HTML_DIR = config.dir.USER_DIR.."/".."html"
config.dir.USER_MENU_DIR = config.dir.USER_DIR.."/".."menu"
config.dir.SYSTEM_HTML_DIR = config.dir.TEMPLATES_DIR.."/".."system"
config.dir.BACKUP_DIR = "backup"

config.MAX_BACKUP_FILES = 20
config.HTTP_PANEL_PORT = 8080


return config
