local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local tl = require("tl")
local lsp = require("tealls.lsp")
local methods = require("tealls.methods")
local util = require("tealls.util")

local document = {}













local ParsedUri = {}







local function find_char(str, chars, pos)
   pos = pos or 1
   local patt = chars:gsub(".", function(c) return "%" .. c end)
   return str:match("(()[" .. patt .. "]())", pos)
end

local function get_next_key_and_chars(char)
   if char == "/" then
      return "path", "?#"
   elseif char == "?" then
      return "query", "#"
   elseif char == "#" then
      return "fragment"
   end
end

function document.parse_uri(uri)
   util.log("Parsing uri: ", uri)
   if not uri then return end


   local parsed = {}
   local last = 1
   do
      local s, e = uri:find("://", 1, true)
      if s then
         parsed.scheme = uri:sub(1, s - 1)
         last = e + 1
      else
         return
      end
   end
   util.log("   scheme: '", parsed.scheme, "'")

   local next_key = "authority"
   local end_chars = "/?#"
   while end_chars do
      local char, s, e = find_char(uri, end_chars, last)
      if s then
         parsed[next_key] = uri:sub(last, s - 1)
         util.log("   ", next_key, ": ", parsed[next_key], "'")
         last = e - 1
         next_key, end_chars = get_next_key_and_chars(char)
      else
         parsed[next_key] = uri:sub(last)
         util.log("   ", next_key, ": '", parsed[next_key], "'")
         break
      end
   end

   return parsed
end

function document.path_from_uri(uri)
   local parsed = document.parse_uri(uri)
   assert(parsed.scheme == "file", "uri " .. tostring(uri) .. " is not a file")
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
            character = err.x,
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
