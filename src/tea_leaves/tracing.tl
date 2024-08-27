
local TraceEntry <const> = require("tea_leaves.trace_entry")
local asserts <const> = require("tea_leaves.asserts")
local uv <const> = require("luv")

local record tracing
end

local _streams:{function(TraceEntry)} = {}

local _level_trace = 0
local _level_debug = 1
local _level_info = 2
local _level_warning = 3
local _level_error = 4

local level_order_from_str <const> :{TraceEntry.Level:integer} = {
   ["TRACE"] = _level_trace,
   ["DEBUG"] = _level_debug,
   ["INFO"] = _level_info,
   ["WARNING"] = _level_warning,
   ["ERROR"] = _level_error,
}

local _min_level:TraceEntry.Level = "TRACE"
local _min_level_number:integer = level_order_from_str[_min_level]

local function get_unix_timestamp():integer
   return os.time()
end

local _load_start_time:number = nil

local function get_ref_time_seconds():number
   return uv.hrtime() / 1e9
end

local function get_relative_time():number
   if _load_start_time == nil then
      _load_start_time = get_ref_time_seconds()
      asserts.is_not_nil(_load_start_time)
   end

   return get_ref_time_seconds() - _load_start_time
end

function tracing._is_level_enabled(_log_module:string, level:integer):boolean
   if _min_level_number > level then
      return false
   end

   if #_streams == 0 then
      return false
   end

   return true
end

function tracing.add_stream(stream:function(TraceEntry))
   asserts.is_not_nil(stream)
   table.insert(_streams, stream)
end

function tracing.get_min_level():TraceEntry.Level
   return _min_level
end

function tracing.set_min_level(level:TraceEntry.Level)
   _min_level = level
   _min_level_number = level_order_from_str[level]
end

local function _process_format_args(message:string):string, {string}, {string}
   local result = {}
   local formats = {}

   -- non greedy match for {} pairs
   local pattern = "{(.-)}"

   local unnamed_arg_counter = 0

   local new_message = string.gsub(message, pattern, function(matched_text:string):string
      local arg_name:string
      if #matched_text == 0 then
         arg_name = tostring(unnamed_arg_counter)
         table.insert(result, arg_name)
         table.insert(formats, "")
         unnamed_arg_counter = unnamed_arg_counter + 1
      else
         local formatting:string
         arg_name, formatting = string.match(matched_text, "([^:]*):?(.*)")
         table.insert(result, arg_name)
         table.insert(formats, formatting)
      end

      return "{" .. arg_name .. "}"
   end)

   return new_message, result, formats
end

local function create_entry(module:string, level:TraceEntry.Level, message_template:string, raw_fields:any):TraceEntry
   if raw_fields == nil then
      raw_fields = {}
   end

   -- Important that we don't include runtime values in the message template, since
   -- this can cause our logic here of extracting args to fail
   asserts.that(#message_template < 200, "Message template is longer than expected.  Are you including runtime values in it?  If so these should be provided as fields instead. Full message: {}", message_template)

   local raw_fields_map = raw_fields as {any:any}
   local fields:{string:any} = {}

   local format_args:{any} = {}

   for key, value in pairs(raw_fields_map) do
      asserts.is_not_nil(value)
      if type(key) == "number" then
         local format_arg_index = key as integer
         while #format_args + 1 < format_arg_index do
            table.insert(format_args, "nil")
         end
         table.insert(format_args, value)
      else
         asserts.that(type(key) == "string", "Fields table must have string keys for the map section")
         fields[key as string] = value
      end
   end

   local adjusted_message_template, format_arg_names, _arg_formattings = _process_format_args(message_template)

   while #format_arg_names > #format_args do
      table.insert(format_args, "nil")
   end

   if #format_arg_names ~= #format_args then
      asserts.that(#format_arg_names > #format_args,
         "Mismatch between length of format args and format arg names. Given {}, expected {}", #format_args, #format_arg_names)

      -- Forgive nil values since we don't want to crash here and this is a common problem
      for _=#format_args+1,#format_arg_names do
         table.insert(format_args, "nil")
      end
   end

   for i=1,#format_arg_names do
      local arg_name = format_arg_names[i]
      local arg_value = format_args[i]
      asserts.that(fields[arg_name] == nil, "Found both map and non map value for field '{}'", arg_name)
      fields[arg_name] = arg_value
   end

   return {
      timestamp = get_unix_timestamp(),
      time = get_relative_time(),
      level = level,
      module = module,
      fields = fields,
      message = adjusted_message_template,
   }
end

function tracing.log(module:string, level:TraceEntry.Level, message:string, fields:any)
   asserts.is_not_nil(message, "Must provide a non nil value for message")
   asserts.that(fields == nil or type(fields) == "table", "Invalid value for fields")

   local entry = create_entry(module, level, message, fields)

   asserts.is_not_nil(entry.message)

   for _, stream in ipairs(_streams) do
      stream(entry)
   end
end

function tracing.trace(module:string, message:string, fields:{any:any})
   if tracing._is_level_enabled(module, _level_trace) then
      tracing.log(module, "TRACE", message, fields)
   end
end

function tracing.debug(module:string, message:string, fields:{any:any})
   if tracing._is_level_enabled(module, _level_debug) then
      tracing.log(module, "DEBUG", message, fields)
   end
end

function tracing.info(module:string, message:string, fields:{any:any})
   if tracing._is_level_enabled(module, _level_info) then
      tracing.log(module, "INFO", message, fields)
   end
end

function tracing.warning(module:string, message:string, fields:{any:any})
   if tracing._is_level_enabled(module, _level_warning) then
      tracing.log(module, "WARNING", message, fields)
   end
end

function tracing.error(module:string, message:string, fields:{any:any})
   if tracing._is_level_enabled(module, _level_error) then
      tracing.log(module, "ERROR", message, fields)
   end
end

return tracing

