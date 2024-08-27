local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string
local util = require("tea_leaves.util")
local asserts = require("tea_leaves.asserts")
local Path = require("tea_leaves.path")
local TraceEntry = require("tea_leaves.trace_entry")
local json = require("dkjson")
local uv = require("luv")
local class = require("tea_leaves.class")
local inspect = require("inspect")

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
   if not dir:is_directory() then
      dir:create_directory()
   end

   local current_time_sec = os.time()
   local max_age_sec = 60 * 60 * 24

   for _, file_path in ipairs(dir:get_sub_files()) do
      local stats = assert(uv.fs_stat(file_path.value))
      local mod_time_sec = stats.mtime.sec

      if current_time_sec - mod_time_sec > max_age_sec then
         util.try({
            action = function()
               file_path:delete_file()
            end,
            catch = function()

            end,
         })
      end
   end
end

function TraceStream:_get_log_dir()
   local homedir = Path(assert(uv.os_homedir()))
   asserts.that(homedir:exists())
   local log_dir = homedir:join(".cache"):join("tea-leaves")

   if not log_dir:is_directory() then
      log_dir:create_directory()
   end

   return log_dir
end

function TraceStream:_choose_log_file_path()
   local log_dir = self:_get_log_dir()
   self:_cleanup_old_logs(log_dir)

   local date = os.date("*t")
   local pid = uv.os_getpid()

   return log_dir:join(string.format("%d-%d-%d_%d.txt", date.year, date.month, date.day, pid))
end

function TraceStream:initialize()
   asserts.that(not self._is_initializing)
   self._is_initializing = true

   asserts.that(not self._has_initialized)
   self._has_initialized = true

   asserts.is_nil(self._file_stream)

   self._file_stream = _open_write_file(self.log_path.value)
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

   local new_path = self:_get_log_dir():join(new_name .. ".log")
   uv.fs_rename(self._log_path.value, new_path.value)
   self._log_path = new_path
   self._file_stream = _open_write_file_append(self._log_path.value)
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

   local serializable_fields = {}
   for key, value in pairs(entry.fields) do
      asserts.that(type(key) == "string")
      local value_type = type(value)

      if value_type == "thread" then
         value = "<thread>"
      elseif value_type == "function" then
         value = "<function>"
      elseif value_type == "userdata" then
         value = tostring(value)
      elseif value_type == "table" then
         value = inspect(value, { newline = ' ' })
      else

         asserts.that(value_type == "string" or value_type == "number" or value_type == "nil" or value_type == "boolean")
      end

      serializable_fields[key] = value
   end

   asserts.is_not_nil(self._file_stream)
   local old_fields = entry.fields
   entry.fields = serializable_fields

   util.try({
      action = function()
         self._file_stream:write(json.encode(entry) .. "\n")
      end,
      finally = function()
         entry.fields = old_fields
      end,
   })

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
