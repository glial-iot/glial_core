#!/usr/bin/env tarantool

local influx_storage = {}
local http_client = require('http.client').new({50})
local box = box
local ts_list = {}


ts_list["/glue/tarantool_arena_used_ratio"] = true
ts_list["/glue/tarantool_arena_size"] = true
ts_list["/glue/tarantool_arena_used"] = true
ts_list["/glue/tarantool_quota_used_ratio"] = true
ts_list["/glue/max_seq_value"] = true
ts_list["/glue/rps_i"] = true
ts_list["/glue/rps_o"] = true
ts_list["/glue/avg_seq_value"] = true


ts_list["/wb-map12h/Ch 1 P L1"] = "/wb-map12h/Ch_1_P_L1"
ts_list["/wb-map12h/Ch 1 P L2"] = "/wb-map12h/Ch_1_P_L2"
ts_list["/wb-map12h/Ch 1 P L3"] = "/wb-map12h/Ch_1_P_L3"
ts_list["/wb-map12h/Ch 1 Total P"] = "/wb-map12h/Ch_1_Total_P"

ts_list["/wb-map12h/Ch 1 Irms L1"] = "/wb-map12h/Ch_1_Irms_L1"
ts_list["/wb-map12h/Ch 1 Irms L2"] = "/wb-map12h/Ch_1_Irms_L2"
ts_list["/wb-map12h/Ch 1 Irms L3"] = "/wb-map12h/Ch_1_Irms_L3"

ts_list["/wb-map12h/Ch 1 AP energy L1"] = "/wb-map12h/Ch_1_AP_energy_L1"
ts_list["/wb-map12h/Ch 1 AP energy L2"] = "/wb-map12h/Ch_1_AP_energy_L2"
ts_list["/wb-map12h/Ch 1 AP energy L3"] = "/wb-map12h/Ch_1_AP_energy_L3"

ts_list["/wb-map12h/Urms L1"] = "/wb-map12h/UrmsL1"
ts_list["/wb-map12h/Frequency"] = "/wb-map12h/Frequency"

ts_list["/mercury200/Power"] = "/mercury200/Power"
ts_list["/mercury200/Power consumption tariff 1"] = "/mercury200/Power_consumption_tariff_1"
ts_list["/mercury200/Power consumption tariff 2"] = "/mercury200/Power_consumption_tariff_2"
ts_list["/mercury200/Power consumption tariff 3"] = "/mercury200/Power_consumption_tariff_3"
ts_list["/mercury200/Voltage"] = "/mercury200/Voltage"

ts_list["/wb-w1/28-000008e538e6"] = "/wb-w1/28-000008e538e6"
ts_list["/wb-w1/28-000008e7f176"] = "/wb-w1/28-000008e7f176"

ts_list["/vaisala/CO"] = "/vaisala/CO"
ts_list["/vaisala/H2S"] = "/vaisala/H2S"
ts_list["/vaisala/Ha"] = "/vaisala/Ha"
ts_list["/vaisala/Hd"] = "/vaisala/Hd"
ts_list["/vaisala/Hi"] = "/vaisala/Hi"
ts_list["/vaisala/NO2"] = "/vaisala/NO2"
ts_list["/vaisala/PAa"] = "/vaisala/PAa"
ts_list["/vaisala/PAw"] = "/vaisala/PAw"
ts_list["/vaisala/PM10"] = "/vaisala/PM10"
ts_list["/vaisala/PM25"] = "/vaisala/PM25"
ts_list["/vaisala/RHa"] = "/vaisala/RHa"
ts_list["/vaisala/RHw"] = "/vaisala/RHw"
ts_list["/vaisala/Ra_mm"] = "/vaisala/Ra_mm"
ts_list["/vaisala/Ra_mmh"] = "/vaisala/Ra_mmh"
ts_list["/vaisala/Ra_s"] = "/vaisala/Ra_s"
ts_list["/vaisala/SO2"] = "/vaisala/SO2"
ts_list["/vaisala/STATa"] = "/vaisala/STATa"
ts_list["/vaisala/STATw"] = "/vaisala/STATw"
ts_list["/vaisala/Ta"] = "/vaisala/Ta"
ts_list["/vaisala/Tw"] = "/vaisala/Tw"
ts_list["/vaisala/WD"] = "/vaisala/WD"
ts_list["/vaisala/WDMAX"] = "/vaisala/WDMAX"
ts_list["/vaisala/WDMIN"] = "/vaisala/WDMIN"
ts_list["/vaisala/WS"] = "/vaisala/WS"
ts_list["/vaisala/WSMAX"] = "/vaisala/WSMAX"
ts_list["/vaisala/WSMIN"] = "/vaisala/WSMIN"



function influx_storage.init()

end


function influx_storage.handler(db, topic, value)
   if (ts_list[topic] ~= nil) then
      if (ts_list[topic] == true) then
         influx_storage.update_value(db, topic, value)
      else
         influx_storage.update_value(db, ts_list[topic], value)
      end
   end
end

function influx_storage.update_value(db, topic, value)
   local data = string.format('%s value=%s', topic, tonumber(value) or 0)
   local url = string.format('http://influxdb:8086/write?db=%s', db)
   local r = http_client:post(url, data, {timeout = 1})
   return r.body
end



return influx_storage

