local event = {}
event.endpoint = "/action2"
event.name = "test_http_event"
event.active = true
event.event_function = function(req)
   local inspect = require 'inspect'
   local logger = require 'logger'
   local params = req:param()

   logger.add_entry(logger.INFO, "test_http_event", inspect(params))
end
return event
