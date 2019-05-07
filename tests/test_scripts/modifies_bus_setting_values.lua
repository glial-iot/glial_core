function init()
    -- If setting exists
    local setting_bool, setting_value, setting_name, setting_description = get_settings_value("test_setting")
    update({topic = "/test/functions/setting_bool", value = setting_bool})
    update({topic = "/test/functions/setting_value", value =  setting_value})
    update({topic = "/test/functions/setting_name", value =  setting_name})
    update({topic = "/test/functions/setting_description", value =  setting_description})

    -- If setting doesn't exist, but function called with default value
    local unex_setting_bool, unex_setting_value = get_settings_value("unexisting_setting", 200)
    update({topic = "/test/functions/unex_setting_bool", value = unex_setting_bool})
    update({topic = "/test/functions/unex_setting_value", value =  unex_setting_value})

    -- If setting doesn't exist
    local real_unex_setting_bool = get_settings_value("unexisting_setting")
    update({topic = "/test/functions/real_unex_setting_bool", value = real_unex_setting_bool})

end

function destroy()

end