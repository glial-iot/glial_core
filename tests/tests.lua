require 'busted.runner'()
local http = require "socket.http"
local ltn12 = require "ltn12"
local md5 = require "md5"
local base64 = require "base64"
local inspect = require 'inspect'
local fun = require 'fun'
local json = require "json"

math.randomseed(os.time())

require("functions")

describe("Launch #tarantool (required for #script, #logs, #bus, #functions and #backups tests)" , function()
    test("Make system call to launch Glue with parameters", function()
        local tarantool_pid = startTarantool()
        assert.are_not.equal(false, tarantool_pid)
        assert.are_not.equal(nil, tarantool_pid)
    end)
end)

describe("Testing basic #script system functionality", function()
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


describe("Testing advanced #script system functionality", function()

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
        local launched_invalid_script = getScriptByUuid("driver", driver_script.uuid)
        assert.are.equal("ERROR", launched_invalid_script.status)
    end)

    test("Create valid script, launch it and get no errors", function()
        local driver_script = createScriptFromFile("driver", "./test_scripts/valid_script.lua")
        setScriptActiveFlag("driver", driver_script.uuid, "ACTIVE")
        local launched_valid_script = getScriptByUuid("driver", driver_script.uuid)
        assert.are.equal("NORMAL", launched_valid_script.status)
    end)

    test("Create script that modifies bus, launch it and check that bus is updated", function()
        local modifies_bus_script = createScriptFromFile("driver", "./test_scripts/modifies_bus.lua")
        setScriptActiveFlag("driver", modifies_bus_script.uuid, "ACTIVE")
        sleep(200)
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

        updateBusTopicValue("/test/event_script/bus_value", "specific_value")
        sleep(300)

        local topics = getBusTopicsByMask("/test/event_script/current_status", 1)
        assert.are.equal("success", topics[1].value)

        updateBusTopicValue("/test/event_script/bus_value", "not_specific_value")
        sleep(300)

        topics = getBusTopicsByMask("/test/event_script/current_status", 1)
        assert.are.equal("reverted", topics[1].value)
    end)

end)


describe("Testing #bus", function()

    test("Create topic with value, update it and check updated", function()

        updateBusTopicValue("/test/bus_test/create_topic", "test_value")
        sleep(200)
        local topics = getBusTopicsByMask("/test/bus_test/create_topic", 1)
        assert.are.equal("test_value", topics[1].value)

        updateBusTopicValue("/test/bus_test/create_topic", "test_value2")
        sleep(200)
        local topics = getBusTopicsByMask("/test/bus_test/create_topic", 1)
        assert.are.equal("test_value2", topics[1].value)

    end)

    test("Change topic metadata", function()

        local topic_name = "/test/bus_test/metadata_topic"
        updateBusTopicValue(topic_name, "metadata_test")
        sleep(200)

        updateBusTopicTags(topic_name, "test_tag")
        updateBusTopicType(topic_name, "sample_type")
        sleep(200)

        local topics = getBusTopicsByMask(topic_name, 1)
        assert.are.equal("metadata_test", topics[1].value)
        assert.are.equal("sample_type", topics[1].type)
        assert.are.equal("test_tag", topics[1].tags)
    end)

    test("Change topic metadata", function()

        local topic_name = "/test/bus_test/metadata_topic"
        updateBusTopicValue(topic_name, "metadata_test")
        sleep(200)

        updateBusTopicTags(topic_name, "test_tag")
        updateBusTopicType(topic_name, "sample_type")
        sleep(200)

        local topics = getBusTopicsByMask(topic_name, 1)
        assert.are.equal("metadata_test", topics[1].value)
        assert.are.equal("sample_type", topics[1].type)
        assert.are.equal("test_tag", topics[1].tags)

    end)

    test("Delete topic from bus", function()
        local topic_name = "/test/bus_test/topic_to_be_deleted"
        updateBusTopicValue(topic_name, "sample_value")
        sleep(200)
        deleteBusTopic(topic_name)
        sleep(200)

        local topics = getBusTopicsByMask(topic_name, 1)
        assert.are.equal('true', topics["none_data"])
    end)
end)

describe("Testing #logs", function()

    test("Create log entries (different levels)", function()

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

    test("Get logs sorted by level (filter check)", function()

        local levels = {"ERROR", "WARNING", "INFO", "USER"}

        for iteration, value in ipairs(levels) do

            local logs_string = inspect(getLogs(nil, value))
            local unwanted_levels = levels
            unwanted_levels[iteration] = nil

            for i, unwanted_value in ipairs(unwanted_levels) do
                assert.are.equal(nil, string.match(logs_string, unwanted_value))
            end

            assert.are_not.equal(nil, string.match(logs_string, value))
        end

    end)

    test("Delete all logs", function()

        local creates_logs_script = createScriptFromFile("driver", "./test_scripts/creates_logs.lua")
        setScriptActiveFlag("driver", creates_logs_script.uuid, "ACTIVE")
        sleep(300)

        local logs_string =inspect(getLogs(creates_logs_script.uuid))
        assert.are_not.equal(nil, string.match(logs_string, creates_logs_script.name))

        deleteAllLogs()
        sleep(200)
        local logs_string_after_delete = inspect(getLogs(creates_logs_script.uuid))
        assert.are.equal(nil, string.match(logs_string_after_delete, creates_logs_script.name))

    end)

end)

describe("Testing #backups", function()

    test("Check backup creation, wipe and restore from backup.)", function()
        -- Save initial glue pid for further checks
        local initial_glue_pid = getGluePid()

        -- Create scripts that write to logs and bus.
        local creates_logs_script = createScriptFromFile("driver", "./test_scripts/creates_logs.lua")
        setScriptActiveFlag("driver", creates_logs_script.uuid, "ACTIVE")
        sleep(200)

        local modifies_bus_script = createScriptFromFile("driver", "./test_scripts/modifies_bus_for_backups.lua")
        setScriptActiveFlag("driver", modifies_bus_script.uuid, "ACTIVE")
        sleep(200)

        -- Check that scripts are created
        local scripts_list = getScriptsList("driver")
        assert.are_not.equal(nil, string.match(scripts_list, creates_logs_script.name))
        assert.are_not.equal(nil, string.match(scripts_list, modifies_bus_script.name))

        -- Check that logs are created
        local logs_string = inspect(getLogs())
        assert.are_not.equal(nil, string.match(logs_string, creates_logs_script.name))

        -- Check that bus topic is created
        local bus_topics = getBusTopicsByMask("/test/modify_bus/for_backups", 1)
        assert.are.equal("modified_for_backup", bus_topics[1].value)

        -- Create user backup
        local backup = createBackup()
        sleep(300)

        -- Wipe storage, restart Glue and check that PID has changed
        local wipe_time = os.time()*1000
        wipeStorage()
        sleep(1000)
        restartTarantool()
        sleep(1000)
        local glue_pid_start_after_wipe = getGluePid()
        assert.is_not_false(glue_pid_start_after_wipe)
        assert.are_not.equal(initial_glue_pid, glue_pid_start_after_wipe)

        -- Check that there are no old logs after wipe.
        local logs_after_restart = getLogs()
        fun.each(function(x)
            assert.is_true(x.time_ms >= wipe_time)
        end, logs_after_restart)

        -- Check that there are no old drivers after wipe
        local scripts_list_after_wipe = getScriptsList("driver")
        assert.are.equal(nil, string.match(scripts_list_after_wipe, creates_logs_script.name))
        assert.are.equal(nil, string.match(scripts_list_after_wipe, modifies_bus_script.name))

        -- Check that there are no old bus topics after wipe
        local bus_topics_after_wipe = getBusTopicsByMask("/test/modify_bus/for_backups", 1)
        assert.are.equal('true', bus_topics_after_wipe["none_data"])

        -- Get latest user backup and restore it
        local latest_backup = getLatestUserBackup()
        local restore_status = restoreBackup(latest_backup.filename)
        assert.are.equal(true, restore_status.result)
        sleep(3000)

        -- Check that Glue is stopped after backup restore
        local glue_pid_after_restore = getGluePid()
        assert.is_false(glue_pid_after_restore)

        -- Start Glue after backup restore and check that it's pid changed
        startTarantool()
        local glue_pid_start_after_restore = getGluePid()
        assert.is_not_false(glue_pid_start_after_restore)
        assert.are_not.equal(glue_pid_start_after_wipe, glue_pid_start_after_restore)

        -- Check that drivers are restored
        local scripts_list_after_restore = getScriptsList("driver")
        assert.are_not.equal(nil, string.match(scripts_list_after_restore, creates_logs_script.name))
        assert.are_not.equal(nil, string.match(scripts_list_after_restore, modifies_bus_script.name))

        -- Check that bus topics are restored
        local bus_topics_after_restore = getBusTopicsByMask("/test/modify_bus/for_backups", 1)
        assert.are.equal("modified_for_backup", bus_topics_after_restore[1].value)

        -- Check that no log entries were restored from backup
        local logs_after_restore = getLogs()
        fun.each(function(x)
            assert.is_true(x.time_ms >= wipe_time)
        end, logs_after_restore)
    end)

end)

describe("Testing #functions", function()

    test("Check round() function.", function()
        -- Create driver that writes rounded values to bus
        local round_function_script = createScriptFromFile("driver", "./test_scripts/modifies_bus_round.lua")
        setScriptActiveFlag("driver", round_function_script.uuid, "ACTIVE")
        sleep(200)

        -- Check that script is created
        local scripts_list = getScriptsList("driver")
        assert.are_not.equal(nil, string.match(scripts_list, round_function_script.name))
        sleep(200)

        -- Check that bus contains rounded and initial values.
        local bus_topic_initial = getBusTopicsByMask("/test/functions/initial_value", 1)
        local bus_topic_rounded = getBusTopicsByMask("/test/functions/rounded_value", 1)
        assert.are.equal(0.6789123, tonumber(bus_topic_initial[1].value))
        assert.are.equal(0.68, tonumber(bus_topic_rounded[1].value))

    end)

    test("Check deepcopy() function.", function()
        -- Create driver that creates table, saves table values to bus,
        -- uses deepcopy()to create another table and saves its' values to bus too.
        local deepcopy_function_script = createScriptFromFile("driver", "./test_scripts/modifies_bus_deepcopy.lua")
        setScriptActiveFlag("driver", deepcopy_function_script.uuid, "ACTIVE")
        sleep(500)

        -- Check that script is created
        local scripts_list = getScriptsList("driver")
        assert.are_not.equal(nil, string.match(scripts_list, deepcopy_function_script.name))
        sleep(200)

        -- Check that bus contains initial table (that was sent when script started), copied table contains modified data
        -- and initial table's data wasn't modified by modification of copied table (no reference).
        local initial_table_foo = getBusTopicsByMask("/test/test_deepcopy/initial_table/foo", 1)
        local initial_table_bar = getBusTopicsByMask("/test/test_deepcopy/initial_table/bar", 1)
        local initial_table_foobar = getBusTopicsByMask("/test/test_deepcopy/initial_table/foobar", 1)
        assert.are.equal("bar", initial_table_foo[1].value)
        assert.are.equal("123", initial_table_bar[1].value)
        assert.are.equal("true", initial_table_foobar[1].value)

        local copied_table_modified_foo = getBusTopicsByMask("/test/test_deepcopy/copied_table_modified/foo", 1)
        local copied_table_modified_bar = getBusTopicsByMask("/test/test_deepcopy/copied_table_modified/bar", 1)
        local copied_table_modified_foobar = getBusTopicsByMask("/test/test_deepcopy/copied_table_modified/foobar", 1)
        assert.are.equal("new", copied_table_modified_foo[1].value)
        assert.are.equal("321", copied_table_modified_bar[1].value)
        assert.are.equal("false", copied_table_modified_foobar[1].value)

        local initial_table_not_modified_foo = getBusTopicsByMask("/test/test_deepcopy/initial_table_not_modified/foo", 1)
        local initial_table_not_modified_bar = getBusTopicsByMask("/test/test_deepcopy/initial_table_not_modified/bar", 1)
        local initial_table_not_modified_foobar = getBusTopicsByMask("/test/test_deepcopy/initial_table_not_modified/foobar", 1)
        assert.are.equal("bar", initial_table_not_modified_foo[1].value)
        assert.are.equal("123", initial_table_not_modified_bar[1].value)
        assert.are.equal("true", initial_table_not_modified_foobar[1].value)

    end)

end)

test("Kill #tarantool (required for #script, #logs, #bus, #functions and #backups tests)", function()
    local tarantool_status = stopTarantool()
    assert.is_false(tarantool_status)
end)


