#!/usr/bin/env tarantool
local scripts_drivers = {}
local scripts_drivers_functions = {}
local logger = require 'logger'
local inspect = require 'libs/inspect'
local system = require 'system'


function scripts_drivers.init(path)
   local error_msg, result

   result = system.dir_check(path)
   if (result ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Drivers directory "'..path..'" not exist and not created')
      return
   end

   local files =  system.get_files_in_dir(path, ".+%.lua")

   for i, filename in pairs(files) do
      result, error_msg = system.script_file_load(filename, scripts_drivers_functions)
      if (result ~= true) then
         logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver not load: "'..error_msg..'"')
      end
   end


   for i, item in pairs(scripts_drivers_functions) do
      if (item ~= nil) then
         if (type(item) == "table") then
            if (item.active == true) then
               local status, err_msg = pcall(item.driver_function)
               if (status == true) then
                  logger.add_entry(logger.INFO, "Drivers subsystem", 'Driver "'..item.name..'" start (active)')
               else
                  logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver "'..item.name..'" not start (internal error: '..(err_msg or "")..')')
               end
            else
               logger.add_entry(logger.INFO, "Drivers subsystem", 'Driver "'..item.name..'" not start (non-active)')
            end
         else
            logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver '..i..' not table', inspect(scripts_drivers_functions))
         end
      else
         logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver '..i..' nil', inspect(scripts_drivers_functions))
      end
   end

end


return scripts_drivers
