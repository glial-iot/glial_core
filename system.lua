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

function system.git_version(new_flag)
   if (git_version == nil or new_flag == true) then
      local handle = io.popen("git describe --dirty --always --tags")
      _, _, git_version = string.find(handle:read("*a"), "(%S+)%s*$")
      handle:close()
      git_version = git_version or "Version git error"
      return git_version
   else
      return git_version
   end
end


return system
