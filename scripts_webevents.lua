#!/usr/bin/env tarantool
local scripts_webevents = {}

local inspect = require 'libs/inspect'

local logger = require 'logger'
local http_system = require 'http_system'
local system = require 'system'

local scripts_webevents_functions = {}

function scripts_webevents.init(path)
   local error_msg, result

   local files =  system.get_files_in_dir(path, ".+%.lua")

   for i, filename in pairs(files) do
      result, error_msg = system.script_file_load(filename, scripts_webevents_functions)
      if (result ~= true) then
         logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event not load: "'..error_msg..'"')
      end
   end

   for i, item in pairs(scripts_webevents_functions) do
      if (item ~= nil) then
         if (type(item) == "table") then
            if (item.endpoint ~= nil) then
               if (item.active == true) then
                  http_system.server:route({ path = item.endpoint, file = item.file_endpoint }, item.event_function)
                  logger.add_entry(logger.INFO, "Web-events subsystem", 'Web-event "'..item.name..'" bind endpoint "'..item.endpoint..'"')
               else
                  logger.add_entry(logger.INFO, "Web-events subsystem", 'Web-event "'..item.name..'" not bind endpoint "'..item.endpoint..'" (not-active)')
               end
            else
               logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event endpoint "'..item.name..'" nil')
            end
         else
            logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event '..i..' not table', inspect(scripts_webevents_functions))
            print(inspect(scripts_webevents_functions))
         end
      else
         logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event '..i..' nil', inspect(scripts_webevents_functions))
      end
   end

end

return scripts_webevents
