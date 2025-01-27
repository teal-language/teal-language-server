
local inspect <const> = require("inspect")

local record tracing_util
end

-- we use our own custom formatting convention here which is:
-- :l = do not add quotes around value
-- @ = serialize the value to string somehow
-- 0*.0* (eg. 0.00, 00.0) = pad zeros and choose decimal amount
function tracing_util.custom_tostring(value:any, formatting:string):string
   local value_type = type(value)

   if formatting == nil or formatting == "" or formatting == "l" then
      if value_type == "thread" then
         return "<thread>"
      elseif value_type == "function" then
         return "<function>"
      elseif value_type == "string" then
         if formatting == "l" then
            return value as string
         else
            return "'" .. (value as string) .. "'"
         end
      else
         return tostring(value)
      end
   end

   if formatting == "@" then
      return inspect(value, { indent = "", newline = " " })
   end

   -- Otherwise, we assume the format string is meant for string.format
   return string.format(formatting, value)
end

function tracing_util.custom_format(message:string, message_args:{any}):string
   local count = 0

   -- non greedy match for {} pairs
   local pattern = "{(.-)}"

   local expanded_message = string.gsub(message, pattern, function(formatting:string):string
      count = count + 1

      local field_value = message_args[count]
      return tracing_util.custom_tostring(field_value, formatting)
   end)

   return expanded_message
end

return tracing_util
