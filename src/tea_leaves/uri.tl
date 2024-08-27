
local asserts <const> = require("tea_leaves.asserts")
local util <const> = require("tea_leaves.util")

--[[
   uri spec:

   foo://example.com:8042/over/there?name=ferret#nose
   \_/   \______________/\_________/ \_________/ \__/
    |           |            |            |        |
 scheme     authority       path        query   fragment
    |   _____________________|__
   / \ /                        \
   urn:example:animal:ferret:nose

   see http://tools.ietf.org/html/rfc3986
]]

local record Uri
   scheme: string
   authority: string
   path: string
   query: string
   fragment: string
end

local function find_patt(str: string, patt: string, pos: integer): string, integer, integer
   pos = pos or 1
   local s, e = str:find(patt, pos)
   if s then
      return str:sub(s, e), s, e
   end
end

local function get_next_key_and_patt(current: string): string, string
   if current == "://" then
      return "authority", "/"
   elseif current == "/" then
      return "path", "[?#]"
   elseif current == "?" then
      return "query", "#"
   elseif current == "#" then
      return "fragment", "$"
   end
end

function Uri.parse(text: string): Uri
   if not text then
      return nil
   end

   -- This is not the most robust uri parser, but we can assume that clients are well behaved
   -- and for the most part we only care about the path
   local parsed <const>: {string:string} = {}
   local last = 1
   local next_key = "scheme"
   local next_patt = "://"

   while next_patt do
      local char <const>, s <const>, e <const> = find_patt(text, next_patt, last)
      parsed[next_key] = text:sub(last, (s or 0) - 1)

      next_key, next_patt = get_next_key_and_patt(char)
      last = (e or last)
         + (next_key == "path" and 0 or 1)
   end

   for k, v in pairs(parsed) do
      if #v == 0 then
         parsed[k] = nil
      end
   end

   -- if authority is present, path can be empty
   if parsed.authority and not parsed.path then
      parsed.path = ""
   end

   -- Hack for windows paths
   -- TODO - reconsider above logic
   if util.get_platform() == "windows" and util.string_starts_with(parsed.path, "/") then
      parsed.path = parsed.path:sub(2)
   end

   -- scheme and path are required
   if not (parsed.scheme and parsed.path) then
      return nil
   end

   -- if authority is not present, path may not begin with '//'
   if not parsed.authority and parsed.path:sub(1, 2) == "//" then
      return nil
   end

   return parsed as Uri
end

function Uri.path_from_uri(s: string): string
   local parsed <const> = Uri.parse(s)
   asserts.that(parsed.scheme == "file", "uri " .. tostring(s) .. " is not a file")
   return parsed.path
end

function Uri.uri_from_path(path: string): Uri
   return {
      scheme = "file",
      authority = "",
      path = path,
      query = nil,
      fragment = nil
   }
end

function Uri.tostring(u: Uri): string
   return u.scheme .. "://"
      .. (u.authority or "")
      .. (u.path or "")
      .. (u.query and "?" .. u.query or "")
      .. (u.fragment and "#" .. u.fragment or "")
end

return Uri
