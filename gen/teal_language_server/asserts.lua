local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string
local asserts = {}


local function _raise(format, ...)
   if format == nil then
      error("Assert hit!")
   else

      if format:find("%%s") ~= nil then
         error("Unexpected assert string - should use {} instead of %s")
      end
      format = format:gsub("{}", "%%s")
      error(string.format(format, ...))
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
