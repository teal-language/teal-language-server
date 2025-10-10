local tracing_util = require("teal_language_server.tracing_util")

local asserts = {}


local function _raise(format, ...)
   if format == nil then
      error("Assert hit!")
   else
      local args = { ... }

      if #args == 0 then
         error(format)
      else
         error(tracing_util.custom_format(format, { ... }))
      end
   end
end

function asserts.fail(format, ...)
   _raise(format, ...)
end
function asserts.that(condition, format, ...)
   if not condition then
      _raise(format, ...)
   end
end

function asserts.is_nil(value, format, ...)
   if value ~= nil then
      if format == nil then
         _raise("Expected nil value but instead found '{}'", value)
      else
         _raise(format, ...)
      end
   end
end

function asserts.is_not_nil(value, format, ...)
   if value == nil then
      if format == nil then
         _raise("Expected non-nil value")
      else
         _raise(format, ...)
      end
   end
end

return asserts
