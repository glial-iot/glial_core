#!/usr/bin/env tarantool

local ts_storage = {}
local box = box

function ts_storage.init()
   ts_storage.object = box.schema.space.create('ts_storage_db', {if_not_exists = true})
   box.schema.sequence.create("ts_storage_db_sequence", {if_not_exists = true})
   ts_storage.object:create_index('primary', {sequence="ts_storage_db_sequence", if_not_exists = true})
   ts_storage.object:create_index('serial_number', {type = 'tree', unique = false, parts = {5, 'string'}, if_not_exists = true })
end

function ts_storage.update_value(topic, value, name)
   local timestamp = os.time()
   ts_storage.object:insert{nil, topic, timestamp, value, name}
end

--sequence[1], topic[2], timestamp[3], value[4], name[5]


return ts_storage
