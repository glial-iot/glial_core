function init()
    local initial_value = 0.6789123
    local rounded_value = round(initial_value)
    update({topic = "/test/functions/initial_value", value = initial_value})
    update({topic = "/test/functions/rounded_value", value =  rounded_value})
end

function destroy()

end