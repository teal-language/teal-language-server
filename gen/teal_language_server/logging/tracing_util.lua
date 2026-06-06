local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string
local inspect = require("inspect")

local tracing_util = {}






function tracing_util.custom_tostring(value, formatting)
   local value_type = type(value)

   if formatting == nil or formatting == "" or formatting == "l" then
      if value_type == "thread" then
         return "<thread>"
      elseif value_type == "function" then
         return "<function>"
      elseif value_type == "string" then
         if formatting == "l" then
            return value
         else
            return "'" .. (value) .. "'"
         end
      else
         return tostring(value)
      end
   end

   if formatting == "@" then
      return inspect(value, { indent = "", newline = " " })
   end


   return string.format(formatting, value)
end

function tracing_util.custom_format(message, message_args)
   local count = 0


   local pattern = "{(.-)}"

   local expanded_message = string.gsub(message, pattern, function(formatting)
      count = count + 1

      local field_value = message_args[count]
      return tracing_util.custom_tostring(field_value, formatting)
   end)

   return expanded_message
end

return tracing_util
