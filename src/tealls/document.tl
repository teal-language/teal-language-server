
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

local function find_patt(str: string, patt: string, pos: number): string, number, number
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

function document.parse_uri(uri: string): ParsedUri
   util.log("Parsing uri: ", uri)
   if not uri then return end

   -- This is not the most robust uri parser, but we can assume that clients are well behaved
   -- and for the most part we only care about the path
   local parsed <const>: {string:string} = {}
   local last = 1
   local next_key = "scheme"
   local end_patt = "://"

   while end_patt do
      local char <const>, s <const>, e <const> = find_patt(uri, end_patt, last)
      parsed[next_key] = uri:sub(last, (s or 0) - 1)
      util.log("   ", next_key, ": '", parsed[next_key], "'")

      next_key, end_patt = get_next_key_and_patt(char)
      last = (e or last) + (next_key == "path" and 0 or 1)
   end

   for k, v in pairs(parsed) do
      if #v == 0 then
         parsed[k] = nil
      end
   end

   if parsed.authority and not parsed.path then
      parsed.path = ""
   end

   -- scheme and path are required
   if not (parsed.scheme and parsed.path) then
      util.log("   missing scheme and/or path, returning nil")
      return nil
   end

   if not parsed.authority and parsed.path:sub(1, 2) == "//" then
      util.log("   path begins with '//' and authority is missing, returning nil")
      return nil
   end

   return parsed as ParsedUri
end

function document.path_from_uri(uri: string): string
   local parsed <const> = document.parse_uri(uri)
   assert(parsed.scheme == "file", "uri " .. tostring(uri) .. " is not a file")
   return parsed.path
end

local function make_diagnostic_from_error(err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   return {
      range = {
         start = {
            line = err.y - 1,
            character = err.x - 1,
         },
         ["end"] = {
            line = err.y - 1,
            character = err.x + 2, -- TODO: get the length of the token here
         },
      },
      severity = lsp.severity[severity],
      message = err.msg .. " ", -- TODO: neovim seems to cut off the last char?
   }
end

local function insert_errors(diagnostics: {lsp.Diagnostic}, errs: {tl.Error}, severity: lsp.Severity)
   for _, err in ipairs(errs) do
      table.insert(diagnostics, make_diagnostic_from_error(err, severity))
   end
end

--[[ TODO
   We currently start from a fresh environment whenever type checking a document,
   by maintaining a dependency graph and keeping a persistent environment (making
   sure to load and unload modules as they get updated) we could probably speed this up
]]

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

