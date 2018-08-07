#!/usr/bin/env tarantool

local export = {}
local fiber = require 'fiber'
local box = box

local logger = require 'logger'

local impact = require 'exports/impact'
local influx = require 'exports/influx'

function export.init()
   impact.init()
   influx.init()
end


function export.send_value(topic, value)
   impact.send_value(topic, value)
   influx.send_value(topic, value)
end



return export

