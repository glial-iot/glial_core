local event = {}
event.endpoint = "/error"
event.name = "test_error_webevent"
event.active = true
event.event_function = function(req)
   local a = 2 / 0
   print_nil(a) (
end

return event
