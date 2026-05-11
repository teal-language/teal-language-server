local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "path_util"

local util = require("teal_language_server.util")
local asserts = require("teal_language_server.asserts")
local uv = require("luv")

local path_util = {}


function path_util.is_absolute(path)
   if util.get_platform() == "windows" then
      return path:match('^[a-zA-Z]:[\\/]') ~= nil
   end

   return util.string_starts_with(path, '/')
end

function path_util.canonicalize(start_path)
   asserts.that(util.get_platform() ~= "windows")

   if start_path:sub(1, 1) ~= "/" then
      local cwd = uv.cwd()
      asserts.that(cwd:sub(1, 1) == "/")
      local adjusted_cwd = path_util.canonicalize(cwd)
      start_path = adjusted_cwd .. "/" .. start_path
   end

   local path_parts = {}

   for part in start_path:gmatch("[^/\\]+") do
      if part == ".." then
         if #path_parts > 0 then
            table.remove(path_parts, #path_parts)
         end
      elseif part ~= "." and part ~= "" then
         table.insert(path_parts, part)
      end
   end
   return "/" .. table.concat(path_parts, "/")
end

function path_util.is_canonical(path)
   return path_util.canonicalize(path) == path
end

return path_util
