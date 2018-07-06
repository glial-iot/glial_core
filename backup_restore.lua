#!/usr/bin/env tarantool
local public = {}
local private = {}

local logger = require 'logger'
local dump = require 'dump'
local config = require 'config'
local system = require 'system'
local fio = require 'fio'

function private.remove_dump_files()
   local exit_code = os.execute("rm -rf ./"..config.dir.DUMP_FILES.."/*  2>&1")
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function private.remove_space_files()
   local files_list = system.get_files_in_dir(config.dir.DUMP_FILES, ".+%.dump")

   for i, filename in pairs(files_list) do
      local _, _, space_number = string.find(filename, "(%d+)%.dump")
      space_number = tonumber(space_number)
      local scripts_space_number = config.id.scripts
      local bus_space_number = config.id.bus
      if (space_number ~= scripts_space_number and space_number ~= bus_space_number) then
         local exit_code = os.execute("rm -f "..filename.." 2>&1")
         if (exit_code ~= 0) then
            return false, "delete space file("..filename..") failed"
         end
      end
   end
   return true
end

function private.archive_dump_files()
   local filename = "gluebackup_"..os.time()..".tar.gz"
   local backup_path = config.dir.BACKUP.."/"..filename
   local files_path = config.dir.DUMP_FILES
   local command = "tar -czf "..backup_path.." "..files_path.." 2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function private.unarchive_dump_files(filename)
   local command = "tar -xf "..filename.."  2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function private.dump()
   local result, msg = dump.dump(config.dir.DUMP_FILES)
   if (result == nil) then
      return false, msg
   end
   return true
end

function private.restore()
   local result = dump.restore(config.dir.DUMP_FILES)
   if (result.rows == 0) then
      return false
   end
   return true, result.rows
end



function public.get_backup_files()
   local files_list = system.get_files_in_dir(config.dir.BACKUP, ".+%.tar.gz")
   table.sort( files_list, function(a,b) return a>b end)
   return files_list
end


function public.remove_old_files()
   local files_list = public.get_backup_files()
   if (#files_list > config.MAX_BACKUP_FILES) then
      for i, filename in pairs(files_list) do
         if (i > config.MAX_BACKUP_FILES) then
            local command = "rm -f "..filename.." 2>&1"
            local exit_code = os.execute(command)
            if (exit_code ~= 0) then
               logger.add_entry(logger.ERROR, "Backup-restore system", "Delete old backup file("..filename..") failed")
            end
         end
      end
   end
end

function public.create_backup()
   local result, msg
   result = private.remove_dump_files()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Backup failed on stage 1")
      return false
   end
   result, msg = private.dump()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Backup failed on stage 2: "..(msg or ""))
      return false
   end
   result = private.archive_dump_files()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Backup failed on stage 3")
      return false
   end
   private.remove_dump_files()
   return true
end

function public.restore_backup(filename)
   if (filename == nil) then
      local files_list = public.get_backup_files()
      filename = files_list[#files_list-1] or files_list[#files_list]
   else
      filename = "./backup/"..filename
   end

   local result, count, msg
   result = private.remove_dump_files()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Restore failed on stage 1")
      return false
   end
   result = private.unarchive_dump_files(filename)
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Restore failed on stage 2")
      return false
   end
   result, msg = private.remove_space_files()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Restore failed on stage 3: "..(msg or ""))
      return false
   end
   result, count = private.restore()
   if (result == false) then
      logger.add_entry(logger.ERROR, "Backup-restore system", "Restore failed on stage 4: "..(count or 0).." count")
      return false
   end
   private.remove_dump_files()
   return true, count
end

return public
