local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local table = _tl_compat and _tl_compat.table or table
local TraceEntry = require("teal_language_server.trace_entry")
local asserts = require("teal_language_server.asserts")
local tracing_util = require("teal_language_server.tracing_util")
local uv = require("luv")

local tracing = {}


local _streams = {}

local _level_trace = 0
local _level_debug = 1
local _level_info = 2
local _level_warning = 3
local _level_error = 4

local level_order_from_str = {
   ["TRACE"] = _level_trace,
   ["DEBUG"] = _level_debug,
   ["INFO"] = _level_info,
   ["WARNING"] = _level_warning,
   ["ERROR"] = _level_error,
}

local _min_level = "TRACE"
local _min_level_number = level_order_from_str[_min_level]

local function get_unix_timestamp()
   return os.time()
end

local _load_start_time = nil

local function get_ref_time_seconds()
   return uv.hrtime() / 1e9
end

local function get_relative_time()
   if _load_start_time == nil then
      _load_start_time = get_ref_time_seconds()
      asserts.is_not_nil(_load_start_time)
   end

   return get_ref_time_seconds() - _load_start_time
end

function tracing._is_level_enabled(_log_module, level)
   if _min_level_number > level then
      return false
   end

   if #_streams == 0 then
      return false
   end

   return true
end

function tracing.add_stream(stream)
   asserts.is_not_nil(stream)
   table.insert(_streams, stream)
end

function tracing.get_min_level()
   return _min_level
end

function tracing.set_min_level(level)
   _min_level = level
   _min_level_number = level_order_from_str[level]
end

local function create_entry(module, level, message_template, message_args)
   if message_args == nil then
      message_args = {}
   end

   local formatted_message = tracing_util.custom_format(message_template, message_args)

   return {
      timestamp = get_unix_timestamp(),
      time = get_relative_time(),
      level = level,
      module = module,
      message = formatted_message,
   }
end

function tracing.log(module, level, message, fields)
   asserts.is_not_nil(message, "Must provide a non nil value for message")
   asserts.that(fields == nil or type(fields) == "table", "Invalid value for fields")

   local entry = create_entry(module, level, message, fields)

   asserts.is_not_nil(entry.message)

   for _, stream in ipairs(_streams) do
      stream(entry)
   end
end

function tracing.trace(module, message, fields)
   if tracing._is_level_enabled(module, _level_trace) then
      tracing.log(module, "TRACE", message, fields)
   end
end

function tracing.debug(module, message, fields)
   if tracing._is_level_enabled(module, _level_debug) then
      tracing.log(module, "DEBUG", message, fields)
   end
end

function tracing.info(module, message, fields)
   if tracing._is_level_enabled(module, _level_info) then
      tracing.log(module, "INFO", message, fields)
   end
end

function tracing.warning(module, message, fields)
   if tracing._is_level_enabled(module, _level_warning) then
      tracing.log(module, "WARNING", message, fields)
   end
end

function tracing.error(module, message, fields)
   if tracing._is_level_enabled(module, _level_error) then
      tracing.log(module, "ERROR", message, fields)
   end
end

return tracing
