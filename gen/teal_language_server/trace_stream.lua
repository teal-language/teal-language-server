local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local string = _tl_compat and _tl_compat.string or string
local util = require("teal_language_server.util")
local asserts = require("teal_language_server.asserts")
local TraceEntry = require("teal_language_server.trace_entry")
local json = require("cjson")
local uv = require("luv")
local class = require("teal_language_server.class")
local path_util = require("teal_language_server.path_util")
local files_util = require("teal_language_server.files_util")

local TraceStream = {}










function TraceStream:__init()
   self._has_initialized = false
   self._is_initializing = false
   self._has_disposed = false
end

local function _open_write_file(path)
   local file = io.open(path, "w+")
   asserts.is_not_nil(file, "Could not open file '{}'", path)
   file:setvbuf("line")
   return file
end

local function _open_write_file_append(path)
   local file = io.open(path, "a")
   asserts.is_not_nil(file, "Could not open file '{}'", path)
   file:setvbuf("line")
   return file
end

function TraceStream:_cleanup_old_logs(dir)

   if not files_util.is_directory(dir) then
      files_util.create_directory(dir)
   end

   local current_time_sec = os.time()
   local max_age_sec = 60 * 60 * 24

   for _, sub_path in ipairs(files_util.get_sub_paths(dir)) do
      if not files_util.is_file(sub_path) then
         goto continue
      end

      local mod_time_sec = files_util.get_modification_time_sec(sub_path)

      if current_time_sec - mod_time_sec > max_age_sec then
         util.try({
            action = function()
               files_util.delete_file(sub_path)
            end,
            catch = function()

            end,
         })
      end

      ::continue::
   end
end

function TraceStream:_get_log_dir()
   local homedir = path_util.canonicalize(assert(uv.os_homedir()))
   asserts.that(files_util.is_directory(homedir))

   local log_dir = homedir .. "/.cache/teal-language-server"

   if not files_util.is_directory(log_dir) then
      files_util.create_directory(log_dir)
   end

   return log_dir
end

function TraceStream:_choose_log_file_path()
   local log_dir = self:_get_log_dir()
   self:_cleanup_old_logs(log_dir)

   local date = os.date("*t")
   local pid = uv.os_getpid()

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

function TraceStream:rename_output_file(new_name)
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

function TraceStream:log_entry(entry)
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
      log_path = function(self)
         if self._log_path == nil then
            self._log_path = self:_choose_log_file_path()
            asserts.is_not_nil(self._log_path)
         end
         return self._log_path
      end,
   },
})

return TraceStream
