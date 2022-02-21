
local util <const> = require("tealls.util")

local DIR_SEP = package.config:sub(1,1)

local path_util <const> = {}

function path_util.is_absolute(path: string): boolean
   local first_char = path:sub(1, 1)
   return first_char == '/' or first_char == '\\'
end

local function remove_end_slashes(path: string): string
   local i = #path
   while true do
      local c = path:sub(i, i)
      if c ~= '/' and c ~= '\\' then
         break
      end
      i = i - 1
   end

   return path:sub(1, i)
end

function path_util.join(left:string, right:string): string
   util.assert(not path_util.is_absolute(right))
   return remove_end_slashes(left) .. DIR_SEP .. right
end

return path_util
