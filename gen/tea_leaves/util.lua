local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall; local _module_name = "util"

local uv = require("luv")
local tracing = require("tea_leaves.tracing")

local util = {TryOpts = {}, }














local _uname_info = nil
local _os_type = nil

local function _get_uname_info()
   if _uname_info == nil then
      _uname_info = uv.os_uname()
      assert(_uname_info ~= nil)
   end

   return _uname_info
end

local function _on_error(error_obj)
   return debug.traceback(error_obj, 2)
end

function util.string_escape_special_chars(value)


   value = value:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")


   return value
end

function util.string_starts_with(str, prefix)
   return str:sub(1, #prefix) == prefix
end

function util.string_split(str, delimiter)



   assert(#str > 0, "Unclear how to split an empty string")

   assert(delimiter ~= nil, "missing delimiter")
   assert(type(delimiter) == "string")
   assert(#delimiter > 0)

   local num_delimiter_chars = #delimiter

   delimiter = util.string_escape_special_chars(delimiter)

   local start_index = 1
   local result = {}

   while true do
      local delimiter_index, _ = str:find(delimiter, start_index)

      if delimiter_index == nil then
         table.insert(result, str:sub(start_index))
         break
      end

      table.insert(result, str:sub(start_index, delimiter_index - 1))

      start_index = delimiter_index + num_delimiter_chars
   end

   return result
end

function util.string_join(delimiter, items)
   assert(type(delimiter) == "string")
   assert(items ~= nil)

   local result = ''
   for _, item in ipairs(items) do
      if #result ~= 0 then
         result = result .. delimiter
      end
      result = result .. tostring(item)
   end
   return result
end

function util.get_platform()
   if _os_type == nil then
      local raw_os_name = string.lower(_get_uname_info().sysname)

      if raw_os_name == "linux" then
         _os_type = "linux"
      elseif raw_os_name:find("darwin") ~= nil then
         _os_type = "osx"
      elseif raw_os_name:find("windows") ~= nil or raw_os_name:find("mingw") ~= nil then
         _os_type = "windows"
      else
         tracing.warning(_module_name, "Unrecognized platform '{}'", { raw_os_name })
         _os_type = "unknown"
      end
   end

   return _os_type
end

function util.try(t)
   local success, ret_value = xpcall(t.action, _on_error)
   if success then
      if t.finally then
         t.finally()
      end
      return ret_value
   end
   if not t.catch then
      if t.finally then
         t.finally()
      end
      error(ret_value, 2)
   end
   success, ret_value = xpcall((function()
      return t.catch(ret_value)
   end), _on_error)
   if t.finally then
      t.finally()
   end
   if success then
      return ret_value
   end
   return error(ret_value, 2)
end

return util
