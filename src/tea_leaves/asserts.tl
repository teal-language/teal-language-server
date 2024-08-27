
local record asserts
end

local function _raise(format:string, ...:any)
   if format == nil then
      error("Assert hit!")
   else
      -- We use convention {} instead of %s to remain compatible with other types of logging
      if format:find("%%s") ~= nil then
         error("Unexpected assert string - should use {} instead of %s")
      end
      format = format:gsub("{}", "%%s")
      error(string.format(format, ...))
   end
end

function asserts.fail(format:string, ...:any)
   _raise(format, ...)
end
function asserts.that(condition:boolean, format:string, ...:any)
   if not condition then
      _raise(format, ...)
   end
end

function asserts.is_nil(value:any, format:string, ...:any)
   if value ~= nil then
      if format == nil then
         _raise("Expected nil value but instead found '{}'", value)
      else
         _raise(format, ...)
      end
   end
end

function asserts.is_not_nil(value:any, format:string, ...:any)
   if value == nil then
      if format == nil then
         _raise("Expected non-nil value")
      else
         _raise(format, ...)
      end
   end
end

return asserts
