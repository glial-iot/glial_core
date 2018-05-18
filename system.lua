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


return system
