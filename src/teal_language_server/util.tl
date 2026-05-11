local _module_name = "util"

local uv <const> = require("luv")
local tracing <const> = require("teal_language_server.tracing")
local asserts <const> = require("teal_language_server.asserts")

local record util
   record TryOpts<T>
      action:function():T
      catch:function(err:any):T
      finally:function()
   end

   enum PlatformType
      "linux"
      "osx"
      "windows"
      "unknown"
   end
end

local _uname_info:uv.UnameInfo = nil
local _os_type:util.PlatformType = nil

local function _get_uname_info():uv.UnameInfo
   if _uname_info == nil then
      _uname_info = uv.os_uname()
      asserts.that(_uname_info ~= nil)
   end

   return _uname_info
end

local function _on_error(error_obj:string):any
  return debug.traceback(error_obj, 2)
end

function util.string_escape_special_chars(value:string):string
   -- gsub is not ideal in cases where we want to do a literal
   -- replace, so to do this just escape all special characters with '%'
   value = value:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
   -- Note that we don't put this all in the return statement to avoid
   -- forwarding the multiple return values causing subtle errors
   return value
end

function util.string_starts_with(str:string, prefix:string):boolean
   return str:sub(1, #prefix) == prefix
end

function util.string_ends_with(str:string, suffix:string):boolean
   return suffix == '' or str:sub(-#suffix) == suffix
end

function util.string_split(str:string, delimiter:string):{string}
   -- Unclear whether this should return {} or {''} so just fail instead
   -- Most split functions do one of these two things so there isn't really a standard here
   -- So force calling code to decide
   asserts.that(#str > 0, "Unclear how to split an empty string")

   asserts.that(delimiter ~= nil, "missing delimiter")
   asserts.that(delimiter is string)
   asserts.that(#delimiter > 0)

   local num_delimiter_chars = #delimiter

   delimiter = util.string_escape_special_chars(delimiter)

   local start_index = 1
   local result:{string} = {}

   while true do
      local delimiter_index, _ = str:find(delimiter, start_index)

      if delimiter_index == nil then
         table.insert(result, str:sub(start_index))
         break
      end

      table.insert(result, str:sub(start_index, delimiter_index-1))

      start_index = delimiter_index + num_delimiter_chars
   end

   return result
end

function util.string_join(delimiter:string, items:{string}):string
   asserts.that(delimiter is string)
   asserts.that(items ~= nil)

   local result = ''
   for _, item in ipairs(items) do
      if #result ~= 0 then
         result = result .. delimiter
      end
      result = result .. tostring(item)
   end
   return result
end

function util.get_platform():util.PlatformType
   if _os_type == nil then
      local raw_os_name = string.lower(_get_uname_info().sysname)

      if raw_os_name == "linux" then
         _os_type = "linux"
      elseif raw_os_name:find("darwin") ~= nil then
         _os_type = "osx"
      elseif raw_os_name:find("windows") ~= nil or raw_os_name:find("mingw") ~= nil then
         _os_type = "windows"
      else
         tracing.warning(_module_name, "Unrecognized platform {}", {raw_os_name})
         _os_type = "unknown"
      end
   end

   return _os_type
end

function util.index_of<T>(list:{T}, item:T):integer
   for i=1,#list do
      if item == list[i] then
         return i
      end
   end

   return -1
end

function util.set<T>(lst: {T}): {T:boolean}
   local s <const> = {}
   for _, v in ipairs(lst) do
      s[v] = true
   end
   return s
end

function util.try<T>(t:util.TryOpts<T>):T
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
  success, ret_value = xpcall((function():T
    return t.catch(ret_value)
  end), _on_error) as (boolean, T)
  if t.finally then
    t.finally()
  end
  if success then
    return ret_value
  end
  return error(ret_value, 2)
end

return util
