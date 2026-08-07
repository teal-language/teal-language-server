local luv <const> = require("luv")
local logging <const> = require("teal_language_server.logging")
local util <const> = require("teal_language_server.util.util")

local record LogFileHandler
   interface LogFile
      log_path: string
      rename_output_file: function(self: LogFile, new_name: string)
      close: function(self: LogFile)
   end

   open_log_file: function(loggering: logging): LogFile
end


local function _open_file(path: string, mode: io.OpenMode): FILE
   local f = io.open(path, mode)
   assert(f, "Could not open log file: " .. path)
   f:setvbuf("line")
   return f
end

-- Base directory for cached data, by platform convention. Everywhere except
-- Windows that is ~/.cache (honouring XDG_CACHE_HOME): developer tooling puts
-- things there on macOS too, so ~/Library/Caches is not worth a separate branch.
local function cache_root(): string
   local homedir = assert(luv.os_homedir(), "Could not determine home directory")

   if util.get_platform() == "windows" then
      -- ~/.cache does not exist on Windows, and a dotfolder in the user profile
      -- is not the convention there
      return os.getenv("LOCALAPPDATA") or (homedir .. "/AppData/Local")
   end

   return os.getenv("XDG_CACHE_HOME") or (homedir .. "/.cache")
end

function LogFileHandler.open_log_file(loggering: logging): LogFileHandler.LogFile
   local root = cache_root()
   local log_dir = root .. "/teal-language-server"

   -- fs_mkdir is mkdir(2), so it will not create intermediate directories, and
   -- the root is not guaranteed to exist (a fresh machine may have no ~/.cache).
   -- Create it first; both calls ignore failure because EEXIST is the normal
   -- case, and a real failure surfaces with a better message from _open_file.
   luv.fs_mkdir(root, 493)
   luv.fs_mkdir(log_dir, 493) -- 0755

   -- Delete log files older than 24 hours
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

   local d = os.date("*t") as {string:integer}
   local filename = string.format("%d-%d-%d_%d.txt", d["year"], d["month"], d["day"], luv.os_getpid())
   local log_path = log_dir .. "/" .. filename

   local file = _open_file(log_path, "w+")

   local handle: LogFileHandler.LogFile = {
      log_path = log_path,
   }

   loggering.logger_func = function(msg: string)
      file:write(msg .. "\n")
   end

   function handle:rename_output_file(new_name: string)
      file:close()
      local new_path = log_dir .. "/" .. new_name .. ".log"
      luv.fs_rename(self.log_path, new_path)
      self.log_path = new_path
      file = _open_file(new_path, "a")
      loggering.logger_func = function(msg: string)
         file:write(msg .. "\n")
      end
   end

   function handle:close()
      file:close()
   end

   return handle
end

return LogFileHandler
