
local tl <const> = require("tl")
local lsp <const> = require("tealls.lsp")
local methods <const> = require("tealls.methods")
local util <const> = require("tealls.util")

local document <const> = {}

--[[
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

local function find_char(str: string, chars: string, pos: number): string, number, number
   pos = pos or 1
   local patt <const> = chars:gsub(".", function(c: string): string return "%" .. c end)
   return str:match("(()[" .. patt .. "]())", pos) as (string, number, number)
end

local function get_next_key_and_chars(char: string): string, string
   if char == "/" then
      return "path", "?#"
   elseif char == "?" then
      return "query", "#"
   elseif char == "#" then
      return "fragment"
   end
end

function document.parse_uri(uri: string): ParsedUri
   util.log("Parsing uri: ", uri)
   if not uri then return end

   -- This is not the most robust uri parser, but we can assume that clients are well behaved
   local parsed <const>: {string:string} = {}
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
      local char <const>, s <const>, e <const> = find_char(uri, end_chars, last)
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

   return parsed as ParsedUri
end

function document.path_from_uri(uri: string): string
   local parsed <const> = document.parse_uri(uri)
   assert(parsed.scheme == "file", "uri " .. tostring(uri) .. " is not a file")
   return parsed.path
end

--[[ TODO
   We currently start from a fresh environment whenever type checking a document,
   by maintaining a dependency graph and keeping a persistent environment (making
   sure to load and unload modules as they get updated) we could probably speed this up
]]

local function make_diagnostic_from_error(err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   return {
      range = {
         start = {
            line = err.y - 1,
            character = err.x - 1,
         },
         ["end"] = {
            line = err.y - 1,
            character = err.x, -- TODO: get the length of the token here
         },
      },
      severity = lsp.severity[severity],
      message = err.msg .. " ",
   }
end

local function insert_errors(diagnostics: {lsp.Diagnostic}, errs: {tl.Error}, severity: lsp.Severity)
   for _, err in ipairs(errs) do
      table.insert(diagnostics, make_diagnostic_from_error(err, severity))
   end
end

function document.type_check(uri: string)
   local name <const> = document.path_from_uri(uri)
   util.log("type checking: ", name)
   local result <const>, err <const> = tl.process(name)
   if not result then
      util.log("   error type checking ", name, ": ", err)
      return
   end
   local diagnostics: {lsp.Diagnostic} = {}
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

