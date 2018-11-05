local system_webevent = {}
local private = {}

local logger = require 'logger'
local system = require 'system'
local fiber = require 'fiber'

function private.update(req)
   local _, version_type = system.version()
   if (version_type == "standalone") then
      return req:render{ json = { result = false, msg = "Standalone mode, update error, use system commands" } }
   end
   local branch_1 = system.os_command("git rev-parse --abbrev-ref HEAD")
   local branch_2 = system.os_command("git symbolic-ref --short HEAD")
   if (branch_1 ~= branch_2 and branch_1 ~= nil) then
      return req:render{ json = { result = false, msg = "Detached head, update error" } }
   end

   local old_version = system.git_version()
   local emessage_1 = system.os_command("git fetch 2>&1")
   local emessage_2 =  system.os_command("git reset --hard origin/"..branch_1.." 2>&1")
   local new_version = system.git_version()
   logger.add_entry(logger.INFO, "Action events", 'System update: '..(old_version or "").." -> "..(new_version or "").." and will be stopped")
   system.wait_and_exit()
   return req:render{ json = { result = true, msg = (emessage_1 or "")..(emessage_2 or "") } }
end

function private.system_action_http_api(req)
   local params = req:param()
   local return_object

   if (params["action"] == "tarantool_stop") then
      logger.add_entry(logger.INFO, "Action events", 'System get command stop on web control page')
      system.wait_and_exit()
      return_object = req:render{ json = { result = true } }
   elseif (params["action"] == "wipe_storage") then
      os.execute("rm -rf ./db")
      system.wait_and_exit()
      return_object = req:render{ json = { result = true } }
   elseif (params["action"] == "get_git_version") then
      local version, version_type = system.version()
      return_object = req:render{ json = { version = version, version_type = version_type } }
   elseif (params["action"] == "get_pid") then
      return_object = req:render{ json = { pid = require('tarantool').pid() } }
   elseif (params["action"] == "update") then
      return_object = private.update(req)
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
