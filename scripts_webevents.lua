#!/usr/bin/env tarantool
local fio = require 'fio'
local logger = require 'logger'
local inspect = require 'inspect'
local http_system = require 'http_system'

local scripts_webevents = {}
local scripts_webevents_functions = {}

local webevents_directory = "webevents"

function scripts_webevents.init()

   if (fio.path ~= nil and fio.path.is_dir(webevents_directory) ~= true) then
      logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event directory not exist')
      return
   end

   for i, item in pairs(fio.listdir(webevents_directory)) do
      if (string.find(item, ".+%.lua") ~= nil) then
         local current_func, error_msg = loadfile(webevents_directory.."/"..item)
         if (current_func == nil) then
            logger.add_entry(logger.ERROR, "Web-events subsystem", 'Web-event not load: "'..error_msg..'"')
         else
            scripts_webevents_functions[i] = current_func()
         end
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
