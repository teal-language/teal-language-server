local _module_name = "util"

local uv <const> = require("luv")
local logging <const> = require("teal_language_server.logging")
local logger = logging.get_logger(_module_name)

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
      assert(_uname_info ~= nil)
   end

   return _uname_info
end

local function _on_error(error_obj:string):any
  return debug.traceback(error_obj, 2)
end

function util.string_starts_with(str:string, prefix:string):boolean
   return str:sub(1, #prefix) == prefix
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
         logger:warning("Unrecognized platform %s", raw_os_name)
         _os_type = "unknown"
      end
   end

   return _os_type
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
