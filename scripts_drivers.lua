#!/usr/bin/env tarantool
local scripts_drivers = {}
local scripts_drivers_functions = {}
local logger = require 'logger'
local inspect = require 'inspect'
local fio = require 'fio'

local drivers_directory = "drivers"

function scripts_drivers.init()

   if (fio.path ~= nil and fio.path.is_dir(drivers_directory) ~= true) then
      logger.add_entry(logger.ERROR, "Drivers subsystem", 'Drivers directory '..drivers_directory..' not exist')
      return
   end

   for i, item in pairs(fio.listdir(drivers_directory)) do
      if (string.find(item, ".+%.lua") ~= nil) then
         local current_func, error_msg = loadfile(drivers_directory.."/"..item)
         if (current_func == nil) then
            logger.add_entry(logger.ERROR, "Drivers subsystem", 'Driver not load: "'..error_msg..'"')
         else
            scripts_drivers_functions[i] = current_func()
         end
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
