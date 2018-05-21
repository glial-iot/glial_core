
local driver = {}
driver.name = "system_stat"
driver.active = true
driver.driver_function = function()
   local fiber = require 'fiber'
   local bus = require 'bus'
   local box = require 'box'
   local system = require 'system'

   local function system_stats()
      while true do
         local stats = system.os_command("uptime")
         stats = string.gsub(stats, ",", ".")

         local _, _, la1, la5, la15 = string.find(stats, "(%d+%.%d+).+(%d+%.%d+).+(%d+%.%d+)")
         --print(stats, la1, la5, la15, tonumber(la1), tonumber(la5), tonumber(la15))
         bus.update_value("/glue/system/la1", tonumber(la1))
         bus.update_value("/glue/system/la5", tonumber(la5))
         bus.update_value("/glue/system/la15", tonumber(la15))

         fiber.sleep(5)
      end
   end
   fiber.create(system_stats)
end
return driver
