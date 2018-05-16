local event = {}
event.endpoint = "/system_actions"
event.name = "system_events"
event.active = true
event.event_function = function(req)

   local logger = require 'logger'
   local params = req:param()
   local result, emessage

   if (params["action"] ~= nil) then

      if (params["action"] == "tarantool_stop") then
         logger.add_entry(logger.INFO, "Action events", 'System stop on web control page')
         os.exit()
      elseif (params["action"] == "wipe_storage") then
         os.execute("rm -rf ./db/*")
         os.exit()
      elseif (params["action"] == "update") then
         local handle = io.popen("git pull 2>&1")
         emessage = handle:read("*a")
         handle:close()
         result = true
      end

      return req:render{ json = { result = result, msg = emessage } }
   end
end

return event
