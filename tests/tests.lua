require 'busted.runner'()
local http = require("socket.http")
local ltn12 = require("ltn12")
local md5 = require("md5")
local base64 = require ("base64")
local inspect = require('inspect')
local fun = require('fun')
local json = require "json"

math.randomseed(os.time())

require("functions")

describe("Launch #tarantool" , function()
    test("Make system call to launch Glue with parameters", function()
        local tarantool_pid = startTarantool()
        assert.are_not.equal(false, tarantool_pid)
        assert.are_not.equal(nil, tarantool_pid)
    end)
end)

describe("Testing basic script system functionality", function()
    describe("Testing script create/delete", function()

        -- TODO: Check special symbols in script name +\/_-%. At the moment + gets deleted, \ gets escaped in name.
        test("Create driver script", function()
            local script = createScript("driver")
            local script_list = getScriptsList("driver")
            assert.are_not.equal(nil, string.match(script_list, script.name))
        end)

        test("Get script", function()
            local created_script = createScript("driver")
            local loaded_script = getScriptByUuid("bus_event", created_script.uuid)
            assert.are.equal(loaded_script.name, created_script.name)
        end)

        test("Get scripts list", function()
            local body = getScriptsList("driver")
            assert.are_not.equal(nil, string.match(body, "uuid"))
        end)

        test("Create bus event script", function()
            local script = createScript("bus_event")
            local body = getScriptsList("bus_event")
            assert.are_not.equal(nil, string.match(body, script.name))
        end)

        test("Create timer event script", function()
            local script = createScript("timer_event")
            local body = getScriptsList("timer_event")
            assert.are_not.equal(nil, string.match(body, script.name))
        end)

        test("Create schedule event script", function()
            local script = createScript("schedule_event")
            local body = getScriptsList("schedule_event")
            assert.are_not.equal(nil, string.match(body, script.name))
        end)

        test("Create web event script", function()
            local script = createScript("web_event")
            local body = getScriptsList("web_event")
            assert.are_not.equal(nil, string.match(body, script.name))
        end)

        test("Activate script", function()
            local script = createScript("schedule_event")
            local script_active = setScriptActiveFlag("schedule_event", script.uuid, "ACTIVE")
            assert.are.equal("ACTIVE", script_active.active_flag)
        end)

        test("Deactivate active script", function()
            local script = createScript("web_event")
            setScriptActiveFlag("web_event", script.uuid, "ACTIVE")
            local script_active = setScriptActiveFlag("web_event", script.uuid, "NON_ACTIVE")
            assert.are.equal("NON_ACTIVE", script_active.active_flag)
        end)

        test("Delete inactive script", function()

            local script = createScript("driver")
            local script_list = getScriptsList("driver")
            assert.are_not.equal(nil, string.match(script_list, script.name))

            local result = deleteScript("driver", script.uuid)
            assert.are.equal(true, result.result)

            local script_list_after_delete = getScriptsList("driver")
            assert.are.equal(nil, string.match(script_list_after_delete, script.name))

        end)

        -- TODO: Active and inactive scripts return different table structure on Delete action!
        test("Delete active script", function()

            local script = createScript("driver")
            local script_list = getScriptsList("driver")
            assert.are_not.equal(nil, string.match(script_list, script.name))

            setScriptActiveFlag("driver", script.uuid, "ACTIVE")

            local result = deleteScript("driver", script.uuid)
            assert.is_table(result)

            local script_list_after_delete = getScriptsList("driver")
            assert.are.equal(nil, string.match(script_list_after_delete, script.name))

        end)


        test("Copy script", function()

            -- Create script
            local script = createScript("bus_event")
            local initial_scripts_list = getScriptsList("bus_event")
            assert.are_not.equal(nil, string.match(initial_scripts_list, script.name))

            -- Copy script and perform all checks
            local script_body = md5.sumhexa(math.random()).."body"
            local copy_script_name = md5.sumhexa(math.random()).."copy_name"

            -- Set script body (to check that it's copied)
            local update_result = updateScriptBody("bus_event", script.uuid, script_body)
            assert.are.equal(update_result.body, script_body)

            -- Copy script
            local copy_result = copyScript("bus_event", script.uuid, copy_script_name)
            assert.are.equal(copy_result.name, copy_script_name)
            assert.are.equal(copy_result.body, script_body)

            -- Check occurrence in list
            local script_list_after_copy = getScriptsList("bus_event")
            assert.are_not.equal(nil, string.match(script_list_after_copy, copy_script_name))

            -- Check copied script body for same content as in original script
            local copied_script = getScriptByUuid("bus_event", copy_result.uuid)
            assert.are.equal(copied_script.body, script_body)
        end)

        test("Rename script", function()
            local initial_script = createScript("bus_event")
            local renamed_script = renameScript("bus_event", initial_script.uuid)
            assert.are_not.equal(initial_script.name, renamed_script.name)
        end)

        test("Change script object", function()
            local initial_script = createScript("schedule_event")
            local changed_script = changeScriptObject("schedule_event", initial_script.uuid)
            assert.are_not.equal(initial_script.object, changed_script.object)
        end)

        test("Change script body", function()
            local initial_script = createScript("schedule_event")
            local script_body = md5.sumhexa(math.random()).."body"
            local update_result = updateScriptBody("bus_event", initial_script.uuid, script_body)
            assert.are.equal(update_result.body, script_body)
        end)
    end)
end)


describe("Testing advanced script system functionality", function()

    describe("Delete script where destroy() returns false", function()

        local script_body = readFile("./test_scripts/destroy_returns_false.lua")
        local driver_script = createScript("driver")
        updateScriptBody("driver", driver_script.uuid, script_body)
        setScriptActiveFlag("driver", driver_script.uuid, "ACTIVE")

        test("Script can't be deleted without Glue restart", function()
            deleteScript("driver", driver_script.uuid)
            local script_list_after_delete = getScriptsList("driver")
            assert.are_not.equal(nil, string.match(script_list_after_delete, driver_script.name))
        end)
        test("Script can be deleted after Glue restart", function()
            restartTarantool()
            deleteScript("driver", driver_script.uuid)
            local script_list_after_delete = getScriptsList("driver")
            assert.are.equal(nil, string.match(script_list_after_delete, driver_script.name))
        end)

    end)

    test("Create invalid script, launch it and get error", function()
        local driver_script = createScriptFromFile("driver", "./test_scripts/invalid_script.lua")
        setScriptActiveFlag("driver", driver_script.uuid, "ACTIVE")
        local launched_invalid_script =  getScriptByUuid("driver", driver_script.uuid)
        assert.are.equal("ERROR", launched_invalid_script.status)
    end)

    test("Create valid script, launch it and get no errors", function()
        local driver_script = createScriptFromFile("driver", "./test_scripts/valid_script.lua")
        setScriptActiveFlag("driver", driver_script.uuid, "ACTIVE")
        local launched_valid_script =  getScriptByUuid("driver", driver_script.uuid)
        assert.are.equal("NORMAL", launched_valid_script.status)
    end)

    test("Create script that modifies bus, launch it and check that bus is updated", function()
        local modifies_bus_script = createScriptFromFile("driver", "./test_scripts/modifies_bus.lua")
        setScriptActiveFlag("driver", modifies_bus_script.uuid, "ACTIVE")
        sleep(100)
        local topics = getBusTopicsByMask("/test/modify_bus/value", 1)
        assert.are.equal("modified", topics[1].value)
    end)

    test("Create script that creates logs, launch it and check that logs are created", function()
        local creates_logs_script = createScriptFromFile("driver", "./test_scripts/creates_logs.lua")
        setScriptActiveFlag("driver", creates_logs_script.uuid, "ACTIVE")
        sleep(300)
        local logs = getLogs(creates_logs_script.uuid)
        local levels = {"ERROR", "WARNING", "INFO", "USER"}
        for iteration, value in ipairs(levels) do
            fun.each(function(x)
                assert.are_not.equal(nil, string.match(x.source, creates_logs_script.name))
            end, fun.filter(function(x)
                return x.level == value and x.source ~= "Drivers subsystem"
            end, logs))
        end
    end)

    -- TODO: API method "update_value" accepts "topic" in plain text without base64 or urlencode.
    describe("Create script that listens to bus events, launch script, generate an event, check that script has reacted to the event", function()
        local object = "/test/event_script/bus_value"
        local bus_event_script = createScriptFromFile("bus_event", "./test_scripts/listens_to_bus_events.lua")
        changeScriptObject ("bus_event", bus_event_script.uuid, object)

        setScriptActiveFlag("bus_event", bus_event_script.uuid, "ACTIVE")
        sleep(300)

        updateBusTopic("/test/event_script/bus_value", "specific_value")
        sleep(300)

        local topics = getBusTopicsByMask("/test/event_script/current_status", 1)
        assert.are.equal("success", topics[1].value)

        updateBusTopic("/test/event_script/bus_value", "not_specific_value")
        sleep(300)

        topics = getBusTopicsByMask("/test/event_script/current_status", 1)
        assert.are.equal("reverted", topics[1].value)
    end)

end)

test("Kill #tarantool", function()
    local tarantool_status = stopTarantool()
    assert.is_false(tarantool_status)
end)


