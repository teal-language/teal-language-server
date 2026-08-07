local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local io = _tl_compat and _tl_compat.io or io; local os = _tl_compat and _tl_compat.os or os; local string = _tl_compat and _tl_compat.string or string; local luv = require("luv")
local logging = require("teal_language_server.logging")
local util = require("teal_language_server.util.util")

local LogFileHandler = {}










local function _open_file(path, mode)
   local f = io.open(path, mode)
   assert(f, "Could not open log file: " .. path)
   f:setvbuf("line")
   return f
end

local function get_cache_root_by_os()
   local homedir = assert(luv.os_homedir(), "Could not determine home directory")

   if util.get_platform() == "windows" then
      return os.getenv("LOCALAPPDATA") or (homedir .. "/AppData/Local")
   end

   return os.getenv("XDG_CACHE_HOME") or (homedir .. "/.cache")
end

function LogFileHandler.open_log_file(loggering)
   local root = get_cache_root_by_os()
   local log_dir = root .. "/teal-language-server"

   luv.fs_mkdir(root, 493)
   luv.fs_mkdir(log_dir, 493)


   local scanner = luv.fs_scandir(log_dir)
   if scanner then
      local max_age_sec = 60 * 60 * 24
      local now = os.time()
      while true do
         local name = luv.fs_scandir_next(scanner)
         if not name then break end
         local full = log_dir .. "/" .. name
         local stat = luv.fs_stat(full)
         if stat and (now - stat.mtime.sec) > max_age_sec then
            luv.fs_unlink(full)
         end
      end
   end

   local d = os.date("*t")
   local filename = string.format("%d-%d-%d_%d.txt", d["year"], d["month"], d["day"], luv.os_getpid())
   local log_path = log_dir .. "/" .. filename

   local file = _open_file(log_path, "w+")

   local handle = {
      log_path = log_path,
   }

   loggering.logger_func = function(msg)
      file:write(msg .. "\n")
   end

   function handle:rename_output_file(new_name)
      file:close()
      local new_path = log_dir .. "/" .. new_name .. ".log"
      luv.fs_rename(self.log_path, new_path)
      self.log_path = new_path
      file = _open_file(new_path, "a")
      loggering.logger_func = function(msg)
         file:write(msg .. "\n")
      end
   end

   function handle:close()
      file:close()
   end

   return handle
end

return LogFileHandler
