function init()
    local initial_value = 0.6789123
    local rounded_value = round(initial_value)
    update_value("/test/functions/initial_value", initial_value)
    update_value("/test/functions/rounded_value", rounded_value)
end

function destroy()

end