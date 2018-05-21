local event = {}
event.topic = "/test"
event.name = "test_error_webevent"
event.active = true
event.event_function = function(topic, value)
   local a = 2 / 0
   print(a)
end

return event
