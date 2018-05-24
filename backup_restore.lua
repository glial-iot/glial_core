#!/usr/bin/env tarantool
local public = {}
local private = {}

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local fio = require 'fio'

function private.fuction_name()

end

function public.create_backup()
   local filename = "backup_"..os.date("%Y-%m-%d-%H-%M-%S")..".tar.gz"
   local backup_path = config.dir.BACKUP_DIR.."/"..filename
   local command = "tar -czf "..backup_path.." "..config.dir.USER_DIR.." 2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      logger.add_entry(logger.INFO, "Backup-restore system", "Backup failed")
   end
end

function public.restore_backup(filename)
   local files_list = public.get_backup_files()
   filename = files_list[10]
   os.execute("rm -rf ./"..config.dir.USER_DIR.."/*  2>&1")
   local command = "tar -xf "..filename.."  2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      logger.add_entry(logger.INFO, "Backup-restore system", "Backup failed")
   end
end

function public.get_backup_files()
   local files_list = system.get_files_in_dir(config.dir.BACKUP_DIR, ".+%.tar.gz")
   table.sort( files_list, function(a,b) return a>b end)
   return files_list
end

function public.remove_old_files()
   local files_list = public.get_backup_files()
   if (#files_list > config.MAX_BACKUP_FILES) then
      for i, filename in pairs(files_list) do
         if (i > config.MAX_BACKUP_FILES) then
            local command = "rm "..filename.." 2>&1"
            local exit_code = os.execute(command)
            if (exit_code ~= 0) then
               logger.add_entry(logger.INFO, "Backup-restore system", "Delete old backup file("..filename..") failed")
            end
         end
      end
   end
end



return public
