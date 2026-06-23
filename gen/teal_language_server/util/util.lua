local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local debug = _tl_compat and _tl_compat.debug or debug; local string = _tl_compat and _tl_compat.string or string; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall; local _module_name = "util.util"

local uv = require("luv")
local logging = require("teal_language_server.logging")
local logger = logging.get_logger(_module_name)

local util = { TryOpts = {} }














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

function util.string_starts_with(str, prefix)
   return str:sub(1, #prefix) == prefix
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
         logger:warning("Unrecognized platform %s", raw_os_name)
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
