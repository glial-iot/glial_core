require 'busted.runner'()
local http = require "socket.http"
local socket = require "socket"
local ltn12 = require "ltn12"
local md5 = require "md5"
local base64 = require "base64"
local inspect = require 'inspect'
local fun = require 'fun'
local json = require "json"

math.randomseed(os.time())
local tarantool_start_cmd = "TIME="..os.time().." LOG_TYPE=NONE ./run_tarantool.sh &"

function makeApiCall (type , method, parameters, payload, web_event_endpoint)
    if payload == nil then payload = "" end
    if web_event_endpoint == nil then web_event_endpoint = "" end

    local tarantool_url = "http://localhost:8888"

    local endpoints = {
        ["timer_event"] = "/timerevents",
        ["schedule_event"] = "/sheduleevents",
        ["driver"] = "/drivers",
        ["web_event"] = "/webevents",
        ["web_event_endpoint"] = "/we/"..web_event_endpoint,
        ["bus_event"] = "/busevents",
        ["backup"] = "/backups",
        ["log"] = "/logger",
        ["system_event"] = "/system_event",
        ["system_bus"] = "/system_bus"
    }
    local active_endpoint = tarantool_url .. endpoints[type]

    local response_body = {}

    if method == "GET" then
        local body, code, headers, status = http.request {
            method = method,
            url = active_endpoint,
            source = ltn12.source.string(parameters),
            headers = {
                ["Content-Length"] = string.len(parameters)
            },
            sink = ltn12.sink.table(response_body)
        }
    end
    if method == "POST" then
        local body, code, headers, status = http.request {
            method = method,
            url = active_endpoint.."?"..parameters,
            source = ltn12.source.string(payload),
            headers = {
                ["Content-Length"] = string.len(payload),
                ["Content-Type"] = "application/x-www-form-urlencoded"
            },
            sink = ltn12.sink.table(response_body)
        }
    end

    return table.concat(response_body), code, headers, status

end

function getGluePid()
    local response_body = makeApiCall("system_event", "GET", "action=get_pid")
    local result = json.decode(response_body)
    if (result ~= nil) then
        return result.pid
    else
        return false
    end
end

function createScript (type)
    local script_name = md5.sumhexa(math.random())
    local result = json.decode(makeApiCall(type, "GET", "action=create&name="..base64.encode(script_name)))
    return result.script
end

function getScriptsList(type)
    return makeApiCall(type, "GET", "action=get_list")
end

function deleteScript(type, uuid)
    return json.decode(makeApiCall(type, "GET", "action=delete&uuid=" .. uuid))
end

function updateScriptBody(type, uuid, script_body)
    local script_body_post_param = "data:text/plain;base64,"..base64.encode(script_body)
    return json.decode(makeApiCall(type, "POST", "action=update_body&uuid=" .. uuid, ""..script_body_post_param))
end

function copyScript(type, uuid, new_name)
    local result = json.decode(makeApiCall(type, "GET", "action=copy&uuid=" .. uuid .. "&name="..base64.encode(new_name)))
    return result.script
end

function getScriptByUuid (type, uuid)
    return json.decode(makeApiCall(type, "GET", "action=get&uuid=" .. uuid))
end

function renameScript (type, uuid)
    local new_script_name = md5.sumhexa(math.random())
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&name=" .. base64.encode(new_script_name)))
end

function changeScriptObject (type, uuid, object)
    local new_script_object = object
    if object == nil then
        new_script_object = md5.sumhexa(math.random())
    end
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&object=" .. base64.encode(new_script_object)))
end

function setScriptActiveFlag (type, uuid, active_flag)
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&active_flag=" .. active_flag))
end

function readFile(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

function startTarantool()
    local tarantool_pid = getGluePid()
    if (tarantool_pid == false) then
        os.execute(tarantool_start_cmd)
        os.execute("sleep 1")
    end
    return getGluePid()
end

function stopTarantool()
    local tarantool_pid = getGluePid()
    if (tarantool_pid ~= false) then
        os.execute("kill ".. tarantool_pid)
        os.execute("sleep 1")
    end
    return getGluePid()
end

function restartTarantool()
    local tarantool_pid = getGluePid()
    if (tarantool_pid ~= false) then
        os.execute("kill ".. tarantool_pid)
        os.execute("sleep 1")
        os.execute(tarantool_start_cmd)
        os.execute("sleep 1")
        return getGluePid()
    else
        os.execute(tarantool_start_cmd)
        os.execute("sleep 1")
        return getGluePid()
    end
end

function createScriptFromFile(type, file_path)
    local script_body = readFile(file_path)
    local script = createScript(type)
    updateScriptBody(type, script.uuid, script_body)
    return script
end

function getBusTopicsByMask(mask, limit)
    return json.decode(makeApiCall("system_bus", "GET", "action=get_bus&mask=" .. base64.encode(mask) .. "&limit=" .. limit))
end

function getLogs(uuid, level, limit)
    local args = {uuid = uuid , level = level, limit = limit}
    local parameters = "action=get_logs"
    for i,v in pairs(args) do
        parameters = parameters.."&"..i.."="..v
    end
    return json.decode(makeApiCall("log", "GET", parameters))
end

function deleteAllLogs()
    return json.decode(makeApiCall("log", "GET", "action=delete_logs"))
end

function sleep (msec)
    local sec = tonumber(msec) / 1000
    socket.sleep(sec)
end

function updateBusTopicValue (topic, value)
    return json.decode(makeApiCall("system_bus", "GET", "action=update_value&topic=" .. topic .. "&value=" .. value))
end

function updateBusTopicTags (topic, tags)
    return json.decode(makeApiCall("system_bus", "GET", "action=update_tags&topic=" .. topic .. "&tags=" .. tags))
end

function updateBusTopicType (topic, type)
    return json.decode(makeApiCall("system_bus", "GET", "action=update_type&topic=" .. topic .. "&type=" .. type))
end

function deleteBusTopic(topic)
    return json.decode(makeApiCall("system_bus", "GET", "action=delete_topics&topic=" .. topic))
end

function createBackup()
    return json.decode(makeApiCall("backup", "GET", "action=create"))
end

function getBackupsList()
    return json.decode(makeApiCall("backup", "GET", "action=get_list"))
end

function restoreBackup(filename)
    return json.decode(makeApiCall("backup", "GET", "action=restore&filename=" .. filename))
end

function wipeStorage()
    os.execute("cd .. && rm -rf ./test_db")
end

function getLatestUserBackup ()
    local backups_list = getBackupsList()
    local recent_backups = {}
    fun.each(function(x)
        table.insert(recent_backups, x)
    end, fun.filter(function(x)
        return x.comment == "User created backup" and string.match(x.time_text, "seconds")
    end, backups_list))
    return recent_backups[1]
end
