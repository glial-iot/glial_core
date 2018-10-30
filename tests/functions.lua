require 'busted.runner'()
local http = require("socket.http")
local ltn12 = require("ltn12")
local md5 = require("md5")
local base64 = require ("base64")
local inspect = require('inspect')
local fun = require('fun')
local json = require "json"

math.randomseed(os.time())

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
        local body, code, headers, status  = http.request {
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
        local body, code, headers, status  = http.request {
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

    return table.concat(response_body), code, headers, status;

end

function createScript (type)
    local script_name = md5.sumhexa(math.random())
    local result = json.decode(makeApiCall(type, "GET", "action=create&name="..script_name))
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
    local result =  json.decode(makeApiCall(type, "GET", "action=copy&uuid=" .. uuid .. "&name="..new_name))
    return result.script
end

function getScriptByUuid (type, uuid)
    return json.decode(makeApiCall(type, "GET", "action=get&uuid=" .. uuid))
end

function renameScript (type, uuid)
    local new_script_name = md5.sumhexa(math.random())
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&name=" .. new_script_name))
end

function changeScriptObject (type, uuid)
    local new_script_object = md5.sumhexa(math.random())
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&object=" .. new_script_object))
end

function setScriptActiveFlag (type, uuid, active_flag)
    return json.decode(makeApiCall(type, "GET", "action=update&uuid=" .. uuid .. "&active_flag=" .. active_flag))
end