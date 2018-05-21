#!/usr/bin/env tarantool

local system = {}
local git_version, _

function system.reverse_table(t)
   local reversedTable = {}
   local itemCount = #t
   for k, v in ipairs(t) do
       reversedTable[itemCount + 1 - k] = v
   end
   return reversedTable
end

function system.round(value, rounds)
   return tonumber(string.format("%."..(tostring(rounds or 2)).."f", value))
end

function system.random_string()
   local digest = require 'digest'
   local rand = digest.urandom(10)
   local rand_crc232 = digest.crc32(tostring(rand))
   return rand_crc232
end

function system.os_command(command)
   local handle = io.popen(command)
   local return_value = handle:read("*a")
   handle:close()
   return return_value
end


function system.git_version(new_flag)
   if (git_version == nil or new_flag == true) then
      _, _, git_version = string.find(system.os_command("git describe --dirty --always --tags"), "(%S+)%s*$")
      git_version = git_version or "Version git error"
      return git_version
   else
      return git_version
   end
end




function system.format_seconds(elapsed_seconds)
   local remainder, weeks, days, hours, minutes, seconds
   local weeksTxt, daysTxt, hoursTxt, minutesTxt, secondsTxt

   weeks = math.floor(elapsed_seconds / 604800)
   remainder = elapsed_seconds % 604800
   days = math.floor(remainder / 86400)
   remainder = remainder % 86400
   hours = math.floor(remainder / 3600)
   remainder = remainder % 3600
   minutes = math.floor(remainder / 60)
   seconds = remainder % 60

   if weeks == 1 then weeksTxt = 'week' else weeksTxt = 'weeks' end
   if days == 1 then daysTxt = 'day' else daysTxt = 'days' end
   if hours == 1 then hoursTxt = 'hour' else hoursTxt = 'hours' end
   if minutes == 1 then minutesTxt = 'minute' else minutesTxt = 'minutes' end
   if seconds == 1 then secondsTxt = 'second' else secondsTxt = 'seconds' end

   if elapsed_seconds >= 604800 then
      return weeks..' '..weeksTxt
   elseif elapsed_seconds >= 86400 then
      return days..' '..daysTxt..', '..hours..' '..hoursTxt
   elseif elapsed_seconds >= 3600 then
      return hours..' '..hoursTxt..', '..minutes..' '..minutesTxt
   elseif elapsed_seconds >= 60 then
      return minutes..' '..minutesTxt
   else
      return seconds..' '..secondsTxt
   end

end


return system
