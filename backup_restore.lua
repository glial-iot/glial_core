#!/usr/bin/env tarantool
local backup_restore = {}
local backup_restore_private = {}

local fiber = require 'fiber'

local logger = require 'logger'
local dump = require 'dump'
local config = require 'config'
local system = require 'system'
local fio = require 'fio'


function backup_restore_private.time_backup()
   while true do
      fiber.sleep(60*60*config.BACKUP_PERIODIC_HOURS)
      backup_restore.create_backup("Periodic backup("..config.BACKUP_PERIODIC_HOURS.."h)")
   end
end


function backup_restore_private.remove_dump_files()
   local exit_code = os.execute("rm -rf ./"..config.dir.DUMP_FILES.."/*  2>&1")
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function backup_restore_private.remove_space_files()
   local files_list = system.get_files_in_dir(config.dir.DUMP_FILES, ".+%.dump")

   for i, filename in pairs(files_list) do
      local _, _, space_number = string.find(filename, "(%d+)%.dump")
      space_number = tonumber(space_number)
      local scripts_space_number = config.id.scripts
      local bus_space_number = config.id.bus
      if (space_number ~= scripts_space_number and space_number ~= bus_space_number) then
         local exit_code = os.execute("rm -f '"..filename.."' 2>&1")
         if (exit_code ~= 0) then
            return false, "delete space file("..filename..") failed"
         end
      end
      fiber.yield()
   end
   return true
end

function backup_restore_private.archive_dump_files(comment)
   comment = comment:gsub("%s", "_")
   local filename = "gluebackup_"..os.time().."_"..comment..".tar.gz"
   local backup_path = config.dir.BACKUP.."/"..filename
   local files_path = config.dir.DUMP_FILES
   local command = "tar -czf '"..backup_path.."' '"..files_path.."' 2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function backup_restore_private.unarchive_dump_files(filename)
   local command = "tar -xf '"..filename.."'  2>&1"
   local exit_code = os.execute(command)
   if (exit_code ~= 0) then
      return false
   end
   return true
end

function backup_restore_private.dump()
   local result, msg = dump.dump(config.dir.DUMP_FILES)
   if (result == nil) then
      return false, msg
   end
   return true
end

function backup_restore_private.restore()
   local result = dump.restore(config.dir.DUMP_FILES)
   if (result.rows == 0) then
      return false
   end
   return true, result.rows
end

function backup_restore.get_backup_files()
   local files_list = system.get_files_in_dir(config.dir.BACKUP, ".+%.tar.gz")
   table.sort( files_list, function(a,b) return a>b end)
   return files_list
end


function backup_restore.remove_old_files()
   local files_list = backup_restore.get_backup_files()
   if (#files_list > config.MAX_BACKUP_FILES) then
      for i, filename in pairs(files_list) do
         if (i > config.MAX_BACKUP_FILES) then
            local command = "rm -f '"..filename.."' 2>&1"
            local exit_code = os.execute(command)
            if (exit_code ~= 0) then
               logger.add_entry(logger.ERROR, "Backup-restore system", "Delete old backup file("..filename..") failed")
            end
         end
         fiber.yield()
      end
   end
end

function backup_restore.create_backup(comment)
   local result, msg
   comment = comment or "undefined"
   result = backup_restore_private.remove_dump_files()
   if (result == false) then
      local message = "Backup failed on clear stage"
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result, msg = backup_restore_private.dump()
   if (result == false) then
      local message = "Backup failed on dump stage: "..(msg or "")
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result, msg = backup_restore_private.remove_space_files()
   if (result == false) then
      local message = "Backup failed on space-clean stage: "..(msg or "")
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result = backup_restore_private.archive_dump_files(comment)
   if (result == false) then
      local message = "Backup failed on archive stage"
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   backup_restore_private.remove_dump_files()
   return true
end

function backup_restore.restore_backup(filename)
   if (filename == nil) then
      local files_list = backup_restore.get_backup_files()
      filename = files_list[#files_list-1] or files_list[#files_list]
   end

   local result, count, msg
   fiber.yield()
   result = backup_restore_private.remove_dump_files()
   if (result == false) then
      local message = "Restore failed on clear stage"
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result = backup_restore_private.unarchive_dump_files(filename)
   if (result == false) then
      local message = "Restore failed on dump stage"
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result, msg = backup_restore_private.remove_space_files()
   if (result == false) then
      local message = "Restore failed on space-clean stage: "..(msg or "")
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   fiber.yield()
   result, count = backup_restore_private.restore()
   if (result == false) then
      local message = "Restore failed on restore stage: "..(count or 0).." count"
      logger.add_entry(logger.ERROR, "Backup-restore system", message)
      return false, message
   end
   backup_restore_private.remove_dump_files()
   system.wait_and_exit()
   return true, count
end




------------------↓ HTTP API functions ↓------------------

function backup_restore.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "get_list") then
      local processed_table = {}
      local files_list = backup_restore.get_backup_files()
      local current_time = os.time()
      for i, filename in pairs(files_list) do
         local _, _, time_epoch, comment = string.find(filename, "backup/gluebackup_(%d+)_([A-Za-z0-9_%(%)]+)%.tar%.gz")
         comment = comment or ""
         comment = comment:gsub("_", " ")
         local diff_time_text = system.format_seconds(current_time - (time_epoch or 0)).." ago"
         local time_text = os.date("%Y-%m-%d, %H:%M:%S", time_epoch).." ("..(diff_time_text)..")"
         local size = system.round((fio.lstat(filename).size / 1000), 1)
         table.insert(processed_table, {filename = filename, time = time_epoch, time_text = time_text, comment = comment, size = size})
         fiber.yield()
      end
      return_object = req:render{ json = processed_table }
   elseif (params["action"] == "restore" and params["filename"] ~= nil and params["filename"] ~= "") then
      local result, msg = backup_restore.create_backup("Backup before restore")
      if (result == true) then
         result, msg = backup_restore.restore_backup(params["filename"])
         if (result == true) then
            return_object = req:render{ json = {result = true, error_msg = "Backups API: backup restored"} }
         else
            return_object = req:render{ json = {result = false, error_msg = "Backups API: "..(msg or "")} }
         end
      else
         return_object = req:render{ json = {result = false, error_msg = "Backups API: no create backup before restore("..(msg or "")..")"} }
      end
   elseif (params["action"] == "create") then
      local result, msg = backup_restore.create_backup("User created backup")
      if (result == true) then
         return_object = req:render{ json = {result = true, error_msg = "Backups API: backup created"} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Backups API: no create backup("..(msg or "")..")"} }
      end
   else
      return_object = req:render{ json = {result = false, error_msg = "Backups API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Backups API: Unknown error(238)"} }
   return system.add_headers(return_object)
end




------------------↓ Public functions ↓------------------

function backup_restore.init()
   local http_system = require 'http_system'
   http_system.endpoint_config("/backups", backup_restore.http_api)
   fiber.create(backup_restore_private.time_backup)
end




return backup_restore
