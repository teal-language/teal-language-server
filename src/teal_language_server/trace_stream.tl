
local util <const> = require("teal_language_server.util")
local asserts <const> = require("teal_language_server.asserts")
local TraceEntry <const> = require("teal_language_server.trace_entry")
local json <const> = require("cjson")
local uv <const> = require("luv")
local class <const> = require("teal_language_server.class")
local path_util <const> = require("teal_language_server.path_util")
local files_util <const> = require("teal_language_server.files_util")

local record TraceStream
   _file_stream:FILE
   _has_initialized:boolean
   _is_initializing:boolean
   _has_disposed:boolean
   log_path:string
   _log_path:string

   metamethod __call: function(self: TraceStream): TraceStream
end

function TraceStream:__init()
   self._has_initialized = false
   self._is_initializing = false
   self._has_disposed = false
end

local function _open_write_file(path:string):FILE
   local file = io.open(path, "w+")
   asserts.is_not_nil(file, "Could not open file '{}'", path)
   file:setvbuf("line")
   return file
end

local function _open_write_file_append(path:string):FILE
   local file = io.open(path, "a")
   asserts.is_not_nil(file, "Could not open file '{}'", path)
   file:setvbuf("line")
   return file
end

function TraceStream:_cleanup_old_logs(dir:string)

   if not files_util.is_directory(dir) then
      files_util.create_directory(dir)
   end

   local current_time_sec = os.time()
   local max_age_sec = 60 * 60 * 24 -- 1 day

   for _, sub_path in ipairs(files_util.get_sub_paths(dir)) do
      if not files_util.is_file(sub_path) then
         goto continue
      end

      local mod_time_sec = files_util.get_modification_time_sec(sub_path)

      if current_time_sec - mod_time_sec > max_age_sec then
         util.try {
            action = function():nil
               files_util.delete_file(sub_path)
            end,
            catch = function():nil
               -- ignore if something has the lock for it
            end,
         }
      end

      ::continue::
   end
end

function TraceStream:_get_log_dir():string
   local homedir = path_util.canonicalize(assert(uv.os_homedir()))
   asserts.that(files_util.is_directory(homedir))

   local log_dir = homedir .. "/.cache/teal-language-server"

   if not files_util.is_directory(log_dir) then
      files_util.create_directory(log_dir)
   end

   return log_dir
end

function TraceStream:_choose_log_file_path():string
   local log_dir = self:_get_log_dir()
   self:_cleanup_old_logs(log_dir)

   local date = os.date("*t")
   local pid = uv.os_getpid()
   -- Need to use pid since there can be many instances of teal-language-server running at same time
   return log_dir .. string.format("/%d-%d-%d_%d.txt", date.year, date.month, date.day, pid)
end

function TraceStream:initialize()
   asserts.that(not self._is_initializing)
   self._is_initializing = true

   asserts.that(not self._has_initialized)
   self._has_initialized = true

   asserts.is_nil(self._file_stream)

   self._file_stream = _open_write_file(self.log_path)
   self._is_initializing = false
end

function TraceStream:_close_file()
   asserts.is_not_nil(self._file_stream)
   self._file_stream:close()
end

function TraceStream:rename_output_file(new_name:string)
   if self._file_stream ~= nil then
      self:_close_file()
   end

   local new_path = self:_get_log_dir() .. "/" .. new_name .. ".log"
   uv.fs_rename(self._log_path, new_path)
   self._log_path = new_path
   self._file_stream = _open_write_file_append(self._log_path)
end

function TraceStream:flush()
   if self._has_disposed or self._is_initializing then
      return
   end

   if self._file_stream ~= nil then
      asserts.is_not_nil(self._file_stream)
      self._file_stream:flush()
   end
end

function TraceStream:dispose()
   asserts.that(not self._has_disposed)
   asserts.that(not self._is_initializing)

   self._has_disposed = true

   if not self._has_initialized then
      return
   end

   if self._file_stream ~= nil then
      self:_close_file()
   end
end

function TraceStream:log_entry(entry:TraceEntry):nil
   if self._has_disposed or self._is_initializing then
      return
   end

   if not self._has_initialized then
      self:initialize()
   end

   asserts.is_not_nil(self._file_stream)

   self._file_stream:write(json.encode(entry) .. "\n")
   self._file_stream:flush()
end

class.setup(TraceStream, "TraceStream", {
   nilable_members = { "_file_stream", "_log_path" },
   getters = {
      log_path = function(self:TraceStream):string
         if self._log_path == nil then
            self._log_path = self:_choose_log_file_path()
            asserts.is_not_nil(self._log_path)
         end
         return self._log_path
      end,
   }
})

return TraceStream
