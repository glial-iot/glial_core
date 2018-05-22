#!/usr/bin/env tarantool
local config = {}

config.MQTT_IMPACT_HOST = "impact.iot.nokia.com"
config.MQTT_IMPACT_PORT = 1883
config.MQTT_IMPACT_LOGIN = "TEST_USER"
config.MQTT_IMPACT_PASSWORD = "0wYlg9KJ5E+ksmvt7l2mU6ucSSo/WjRDCdCgd2pQpF0="
config.MQTT_IMPACT_ID = "impact_tarantool_client"
config.MQTT_IMPACT_TOKEN = "trqspu69qcz7"

config.MQTT_WIRENBOARD_HOST = "192.168.1.111"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "glue_"..require('system').random_string()

config.HTTP_PORT = 8080

config.IMPACT_URL = "https://impact.iot.nokia.com"

config.dir = {}
config.dir.USER_DIR = "user"
config.dir.TEMPLATES_DIR = "user"
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


return config
