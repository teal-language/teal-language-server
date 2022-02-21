local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local package = _tl_compat and _tl_compat.package or package; local string = _tl_compat and _tl_compat.string or string
local util = require("tealls.util")

local DIR_SEP = package.config:sub(1, 1)

local path_util = {}

function path_util.is_absolute(path)
   local first_char = path:sub(1, 1)
   return first_char == '/' or first_char == '\\'
end

local function remove_end_slashes(path)
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

function path_util.join(left, right)
   util.assert(not path_util.is_absolute(right))
   return remove_end_slashes(left) .. DIR_SEP .. right
end

return path_util
