function event_handler(value)

    local test_value

    if (value == "specific_value") then
        test_value = "success"
    else
        test_value = "reverted"
    end

    update_value("/test/event_script/current_status", specific_value)

end