#!/usr/bin/env tarantool

local config = {}
config.MQTT_IMPACT_HOST = "impact.iot.nokia.com"
config.MQTT_IMPACT_PORT = 1883
config.MQTT_IMPACT_LOGIN = "TEST_USER"
config.MQTT_IMPACT_PASSWORD = "0wYlg9KJ5E+ksmvt7l2mU6ucSSo/WjRDCdCgd2pQpF0="
config.MQTT_IMPACT_ID = "impact_tarantool_client"
config.MQTT_IMPACT_TOKEN = "trqspu69qcz7"

config.MQTT_WIRENBOARD_HOST = "192.168.1.57"
config.MQTT_WIRENBOARD_PORT = 1883
config.MQTT_WIRENBOARD_ID = "tarantool_client"

config.HTTP_PORT = 8080

config.IMPACT_URL = "https://impact.iot.nokia.com"

return config
