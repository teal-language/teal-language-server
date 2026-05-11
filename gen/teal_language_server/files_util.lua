local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "files_util"

local uv = require("luv")
local util = require("teal_language_server.util")
local path_util = require("teal_language_server.path_util")
local asserts = require("teal_language_server.asserts")

local default_file_permissions = 438
local default_dir_permissions = tonumber('755', 8)

local files_util = {}


function files_util.read_file_as_text(path)
   local fd = assert(uv.fs_open(path, "r", default_file_permissions))

   return util.try({
      action = function()
         local stat = assert(uv.fs_fstat(fd))
         local data = assert(uv.fs_read(fd, stat.size, 0))
         return data
      end,
      finally = function()
         assert(uv.fs_close(fd))
      end,
   })
end


function files_util.try_read_file_as_text(path)
   local fd, _ = uv.fs_open(path, "r", default_file_permissions)

   if fd == nil then
      return nil
   end

   return util.try({
      action = function()
         local stat = assert(uv.fs_fstat(fd))
         local data = assert(uv.fs_read(fd, stat.size, 0))
         return data
      end,
      finally = function()
         assert(uv.fs_close(fd))
      end,
   })
end

function files_util.delete_file(path)
   assert(uv.fs_unlink(path))
end

function files_util.get_modification_time_sec(file_path)
   local stats = assert(uv.fs_stat(file_path))
   return stats.mtime.sec
end

function files_util.try_get_modification_time_ms(file_path)
   local stats = uv.fs_stat(file_path)

   if stats == nil then
      return nil
   end

   return math.floor(stats.mtime.sec + stats.mtime.nsec / 1e6)
end

function files_util.get_modification_time_ms(file_path)
   local stats = assert(uv.fs_stat(file_path))
   return math.floor(stats.mtime.sec + stats.mtime.nsec / 1e6)
end

function files_util.get_sub_paths(path)
   local req, err = uv.fs_scandir(path)

   if req == nil then
      error(string.format("Failed to open dir '%s' for scanning.  Details: '%s'", path, err))
   end

   local function iter()
      local r1, r2 = uv.fs_scandir_next(req)


      if not (r1 ~= nil or (r1 == nil and r2 == nil)) then
         error(string.format("Failure while scanning directory '%s': %s", path, r2))
      end
      return r1, r2
   end

   local result = {}

   for name, _ in iter do
      table.insert(result, path .. "/" .. name)
   end

   return result
end

function files_util.create_directory(path)
   local success, err = uv.fs_mkdir(path, default_dir_permissions)
   if not success then
      error(string.format("Failed to create directory '%s': %s", path, err))
   end
end

function files_util.is_file(file_path)
   local stats = uv.fs_stat(file_path)

   if stats == nil then
      return false
   end

   return stats.type == "file"
end

function files_util.is_directory(file_path)
   local stats = uv.fs_stat(file_path)

   if stats == nil then
      return false
   end

   return stats.type == "directory"
end

function files_util.chdir(path)
   asserts.that(files_util.is_directory(path))
   assert(uv.chdir(path))
end

function files_util.get_sub_paths_recursive(start_dir, extension)
   asserts.that(files_util.is_directory(start_dir))

   local all_paths = {}
   local dir_queue = { start_dir }

   while #dir_queue > 0 do
      local dir = dir_queue[#dir_queue]
      table.remove(dir_queue, #dir_queue)

      for _, sub_path in ipairs(files_util.get_sub_paths(dir)) do
         if files_util.is_directory(sub_path) then
            table.insert(dir_queue, sub_path)

         elseif files_util.is_file(sub_path) and sub_path:sub(-#extension) == extension then
            asserts.that(path_util.is_canonical(sub_path))
            table.insert(all_paths, sub_path)
         end
      end
   end

   return all_paths
end

return files_util
