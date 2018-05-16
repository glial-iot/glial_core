local event = {}
event.endpoint = "/system_actions"
event.name = "system_events"
event.active = true
event.event_function = function(req)

   local logger = require 'logger'
   local system = require 'system'
   local fiber = require 'fiber'
   local params = req:param()
   local result, emessage

   local function wait_and_exit()
      logger.add_entry(logger.INFO, "Action events", 'System stopped')
      fiber.sleep(2)
      os.exit()
   end

   if (params["action"] ~= nil) then

      if (params["action"] == "tarantool_stop") then
         logger.add_entry(logger.INFO, "Action events", 'System get command stop on web control page')
         fiber.create(wait_and_exit)
         result = true
      elseif (params["action"] == "wipe_storage") then
         os.execute("rm -rf ./db/*")
         fiber.create(wait_and_exit)
         result = true
      elseif (params["action"] == "update") then
         local old_version = system.git_version(true)
         local handle = io.popen("git pull 2>&1")
         emessage = handle:read("*a")
         handle:close()
         local new_version = system.git_version(true)
         logger.add_entry(logger.INFO, "Action events", 'System update: '..(old_version or "").." -> "..(new_version or "").." and will be stopped")
         result = true
         fiber.create(wait_and_exit)
      end

      return req:render{ json = { result = result, msg = emessage } }
   end
end

return event
