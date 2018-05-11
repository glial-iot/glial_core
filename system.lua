#!/usr/bin/env tarantool

local system = {}
local git_version

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

function system.git_version()
   if (git_version == nil) then
      local handle = io.popen("git describe --dirty --always --tags")
      git_version = handle:read("*a")
      handle:close()
      return git_version
   else
      return git_version
   end
end


return system
