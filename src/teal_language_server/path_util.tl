local _module_name = "path_util"

local util <const> = require("teal_language_server.util")
local asserts <const> = require("teal_language_server.asserts")
local uv <const> = require("luv")

local record path_util
end

function path_util.is_absolute(path: string): boolean
   if util.get_platform() == "windows" then
      return path:match('^[a-zA-Z]:[\\/]') ~= nil
   end

   return util.string_starts_with(path, '/')
end

function path_util.canonicalize(start_path: string):string
   asserts.that(util.get_platform() ~= "windows") -- TODO

   if start_path:sub(1, 1) ~= "/" then
      local cwd = uv.cwd()
      asserts.that(cwd:sub(1, 1) == "/")
      local adjusted_cwd = path_util.canonicalize(cwd)
      start_path = adjusted_cwd .. "/" .. start_path
   end

   local path_parts: {string} = {}

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

function path_util.is_canonical(path: string):boolean
   return path_util.canonicalize(path) == path
end

return path_util
