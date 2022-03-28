
local util <const> = require("tealls.util")

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

local record ParsedUri
   scheme: string
   authority: string
   path: string
   query: string
   fragment: string
end

local uri <const> = {
   ParsedUri = ParsedUri,
}

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

function uri.parse(text: string): ParsedUri
   if not text then return end

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

   -- scheme and path are required
   if not (parsed.scheme and parsed.path) then
      return nil
   end

   -- if authority is not present, path may not begin with '//'
   if not parsed.authority and parsed.path:sub(1, 2) == "//" then
      return nil
   end

   return parsed as ParsedUri
end

function uri.path_from_uri(s: string): string
   local parsed <const> = uri.parse(s)
   util.assert(parsed.scheme == "file", "uri " .. tostring(s) .. " is not a file")
   return parsed.path
end

function uri.uri_from_path(path: string): ParsedUri
   return {
      scheme = "file",
      authority = "",
      path = path,
      query = nil,
      fragment = nil
   }
end

function uri.tostring(u: ParsedUri): string
   return u.scheme .. "://"
      .. (u.authority or "")
      .. (u.path or "")
      .. (u.query and "?" .. u.query or "")
      .. (u.fragment and "#" .. u.fragment or "")
end

return uri
