#!/usr/bin/env tarantool
local system = {}

local fio = require 'fio'
local fiber = require 'fiber'
local clock = require 'clock'
local inspect = require 'libs/inspect'

local git_version
local version, version_type, _

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

function system.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[system.deepcopy(orig_key)] = system.deepcopy(orig_value)
        end
        setmetatable(copy, system.deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
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

function system.print_n(data, ...)
	io.write(data, ...)
	io.flush()
end

function system.git_version()
   _, _, git_version = string.find(system.os_command("git describe --dirty --always --tags"), "(%S+)%s*$")
   git_version = git_version or "Version git error"
   return git_version
end

function system.version()
   if (version ~= nil and version_type ~= nil) then
      return version, version_type
   else
      _, _, git_version = string.find(system.os_command("git describe --dirty --always --tags"), "(%S+)%s*$")
      if (git_version == nil) then
         local _, _, standalone_version = string.find(system.os_command("cat ./VERSION"), "(%S+)%s*$")
         if (standalone_version == nil) then
            version_type = "standalone"
            version = "Version error"
            return version, version_type
         end
         version_type = "standalone"
         version = standalone_version
         return version, version_type
      else
         version_type = "git"
         version = git_version
         return version, version_type
      end
   end
end

function system.dir_check(dir_path)
   dir_path = dir_path or ""
   if (fio.path.exists(dir_path) ~= true) then
      return fio.mktree(dir_path)
   end
   if (fio.path.is_dir(dir_path) ~= true) then
      return false, dir_path.." is file"
   end
   return true
end

function system.get_files_in_dir(path, mask)
   local files = {}
   local i = 1
   for _, item in pairs(fio.listdir(path)) do
      if (string.find(item, mask) ~= nil) then
         files[i] = path.."/"..item
         i = i + 1
      end
   end
   return files
end

function system.wait_and_exit()
   fiber.create(function()
      require('logger').add_entry(require('logger').INFO, "System", 'System stopped')
      fiber.sleep(1)
      os.exit(1)
   end)
end


function system.add_headers(return_object)
   return_object.headers = return_object.headers or {}
   return_object.headers['Charset'] = 'utf-8';
   return_object.headers['Access-Control-Allow-Origin'] = '*';
   return_object.headers['Content-Type'] = 'application/json';
   return_object.headers['content-type'] = nil;
   return return_object
end

function system.concatenate_args(...)
   local arguments = {...}
   local msg = ""
   local count_args = select("#", ...)
   for i = 1, count_args do
      local new_msg = arguments[i]
      if (type(new_msg) == "table") then
         new_msg = tostring(inspect(new_msg))
      else
         new_msg = tostring(new_msg)
      end
      if (new_msg ~= nil and new_msg ~= "" and type(new_msg) == "string" and type(msg) == "string") then
         msg = msg.."\t"..new_msg
      end
   end
   return msg
end



function system.pcall_timecalc(call_function, ...)
   local start_time = clock.proc64()
   local status, returned_data = pcall(call_function, ...)
   local end_time = clock.proc64()
   local work_time_ms = tonumber(end_time - start_time)/1000/1000
   return status, returned_data, work_time_ms
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
