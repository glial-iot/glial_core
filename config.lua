#!/usr/bin/env tarantool
local system = require 'system'


local config = {}
config.MQTT_IMPACT_HOST = "impact.iot.nokia.com"
config.MQTT_IMPACT_PORT = 1883
config.MQTT_IMPACT_LOGIN = "TEST_USER"
config.MQTT_IMPACT_PASSWORD = "0wYlg9KJ5E+ksmvt7l2mU6ucSSo/WjRDCdCgd2pQpF0="
config.MQTT_IMPACT_ID = "impact_tarantool_client"
config.MQTT_IMPACT_TOKEN = "trqspu69qcz7"

config.MQTT_WIRENBOARD_HOST = "192.168.1.111"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "glue_"..system.random_string()

config.HTTP_PORT = 8080

config.IMPACT_URL = "https://impact.iot.nokia.com"


config.USER_DIR = "user"
config.SYSTEM_DIR = "system_scripts"
config.TIMER_SCRIPTS_DIR = config.USER_DIR.."/".."timer_scripts"
config.EVENT_SCRIPTS_DIR = config.USER_DIR.."/".."events_scripts"
config.WEBEVENT_SCRIPTS_DIR = config.USER_DIR.."/".."webevents_scripts"
config.SYSTEM_WEBEVENT_SCRIPTS_DIR = config.SYSTEM_DIR.."/".."webevents_scripts"
config.DRIVERS_DIR = config.USER_DIR.."/".."drivers"
config.USER_HTML_DIR = "templates".."/".."user"
config.USER_MENU_DIR = config.USER_DIR.."/".."menu"

return config
