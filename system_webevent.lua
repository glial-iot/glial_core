local system_webevent = {}
local private = {}

local logger = require 'logger'
local system = require 'system'
local fiber = require 'fiber'

function private.system_action_http_api(req)
   local params = req:param()
   local return_object

   if (params["action"] == "tarantool_stop") then
      logger.add_entry(logger.INFO, "Action events", 'System get command stop on web control page')
      fiber.create(system.wait_and_exit)
      return_object = req:render{ json = { result = true } }
   elseif (params["action"] == "wipe_storage") then
      os.execute("rm -rf ./db")
      fiber.create(system.wait_and_exit)
      return_object = req:render{ json = { result = true } }
   elseif (params["action"] == "get_git_version") then
      return_object = req:render{ json = { version = system.git_version() } }
   elseif (params["action"] == "get_pid") then
      return_object = req:render{ json = { pid = require('tarantool').pid() } }
   elseif (params["action"] == "update") then
      local old_version = system.git_version(true)
      local emessage_1 = system.os_command("git fetch 2>&1")
      local emessage_2 =  system.os_command("git reset --hard origin/master 2>&1")
      local new_version = system.git_version(true)
      logger.add_entry(logger.INFO, "Action events", 'System update: '..(old_version or "").." -> "..(new_version or "").." and will be stopped")
      return_object = req:render{ json = { result = true, msg = (emessage_1 or "")..(emessage_2 or "") } }
      system.wait_and_exit()
   else
      return_object = req:render{ json = {result = false, error_msg = "Sysevent API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Sysevent API: Unknown error(324)"} }
   return system.add_headers(return_object)
end


function system_webevent.init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/system_event", private.system_action_http_api)
end


return system_webevent
