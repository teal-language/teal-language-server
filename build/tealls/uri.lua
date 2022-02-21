local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string
local util = require("tealls.util")















local ParsedUri = {}







local uri = {
   ParsedUri = ParsedUri,
}

local function find_patt(str, patt, pos)
   pos = pos or 1
   local s, e = str:find(patt, pos)
   if s then
      return str:sub(s, e), s, e
   end
end

local function get_next_key_and_patt(current)
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

function uri.parse(text)
   if not text then return end



   local parsed = {}
   local last = 1
   local next_key = "scheme"
   local next_patt = "://"

   while next_patt do
      local char, s, e = find_patt(text, next_patt, last)
      parsed[next_key] = text:sub(last, (s or 0) - 1)

      next_key, next_patt = get_next_key_and_patt(char)
      last = (e or last) +
      (next_key == "path" and 0 or 1)
   end

   for k, v in pairs(parsed) do
      if #v == 0 then
         parsed[k] = nil
      end
   end


   if parsed.authority and not parsed.path then
      parsed.path = ""
   end


   if not (parsed.scheme and parsed.path) then
      return nil
   end


   if not parsed.authority and parsed.path:sub(1, 2) == "//" then
      return nil
   end

   return parsed
end

function uri.path_from_uri(s)
   local parsed = uri.parse(s)
   util.assert(parsed.scheme == "file", "uri " .. tostring(s) .. " is not a file")
   return parsed.path
end

function uri.uri_from_path(path)
   return {
      scheme = "file",
      authority = "",
      path = path,
      query = nil,
      fragment = nil,
   }
end

function uri.tostring(u)
   return u.scheme .. "://" ..
   (u.authority or "") ..
   (u.path or "") ..
   (u.query and "?" .. u.query or "") ..
   (u.fragment and "#" .. u.fragment or "")
end

return uri