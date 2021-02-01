local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local tl = require("tl")
local lsp = require("tealls.lsp")
local methods = require("tealls.methods")
local util = require("tealls.util")

local document = {}















local ParsedUri = {}







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

function document.parse_uri(uri)
   util.log("Parsing uri: ", uri)
   if not uri then return end



   local parsed = {}
   local last = 1
   local next_key = "scheme"
   local next_patt = "://"

   while next_patt do
      local char, s, e = find_patt(uri, next_patt, last)
      parsed[next_key] = uri:sub(last, (s or 0) - 1)
      util.log("   ", next_key, ": '", parsed[next_key], "'")

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
      util.log("   missing scheme and/or path, returning nil")
      return nil
   end


   if not parsed.authority and parsed.path:sub(1, 2) == "//" then
      util.log("   path begins with '//' and authority is missing, returning nil")
      return nil
   end

   util.log("   Parsed: ", parsed)

   return parsed
end

function document.path_from_uri(uri)
   local parsed = document.parse_uri(uri)
   util.assert(parsed.scheme == "file", "uri " .. tostring(uri) .. " is not a file")
   return parsed.path
end

local function make_diagnostic_from_error(err, severity)
   return {
      range = {
         start = {
            line = err.y - 1,
            character = err.x - 1,
         },
         ["end"] = {
            line = err.y - 1,
            character = err.x + 2,
         },
      },
      severity = lsp.severity[severity],
      message = err.msg .. " ",
   }
end

local function insert_errors(diagnostics, errs, severity)
   for _, err in ipairs(errs) do
      table.insert(diagnostics, make_diagnostic_from_error(err, severity))
   end
end







function document.type_check(uri)
   local name = document.path_from_uri(uri)
   util.log("type checking: ", name)
   local result, err = tl.process(name)
   if not result then
      util.log("   error type checking ", name, ": ", err)
      return
   end
   local diagnostics = {}
   if #result.syntax_errors > 0 then
      insert_errors(diagnostics, result.syntax_errors, "Error")
   else
      insert_errors(diagnostics, result.warnings, "Warning")
      insert_errors(diagnostics, result.unknowns, "Error")
      insert_errors(diagnostics, result.type_errors, "Error")
   end
   methods.publish_diagnostics(uri, diagnostics)
end

return document
