local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local table = _tl_compat and _tl_compat.table or table
local tl = require("tl")
local lsp = require("tealls.lsp")
local methods = require("tealls.methods")
local uri = require("tealls.uri")
local util = require("tealls.util")


local Token = {}




local Node = {}

local Document = {};










(Document).__index = function(self, key)
   if key == "tokens" or key == "syntax_errors" then
      local tks, errs = tl.lex(self.text)
      self.tokens = tks
      self.syntax_errors = errs or {}
   elseif key == "ast" then
      local _
      _, self.ast = (tl.parse_program)(self.tokens)
   elseif key == "result" then
      local res = {
         syntax_errors = {},
         type_errors = {},
         unknowns = {},
         warnings = {},
         dependencies = {},
      };
      (tl.type_check)(self.ast, {
         filename = self.uri.path,
         result = res,
      })
      self.result = res
   end
   return rawget(self, key) or
   rawget(Document, key)
end

local cache = {}
local document = {}

function document.open(iden, content)
   local d = setmetatable({
      uri = type(iden) == "string" and uri.parse(iden) or iden,
      text = content,
   }, Document)
   cache[d.uri.path] = d
   return d
end

function document.close(iden)
   local u = type(iden) == "string" and uri.parse(iden) or iden
   cache[u.path] = nil
end

function document.get(iden)
   local u = type(iden) == "string" and uri.parse(iden) or iden
   return cache[u.path]
end

function Document:replace_text(text)
   self.text = text
   self.tokens = nil
   self.ast = nil
   self.result = nil
end

local function in_range(n, base, length)
   return base <= n and n < base + length
end

local function find_token_at(tks, y, x)
   local _, tk = util.binary_search(tks, function(t)
      return t.y > y and -1 or
      t.y < y and 1 or
      in_range(x, t.x, #t.tk) and 0 or
      t.x > x and -1 or
      1
   end)
   return tk
end

local function make_diagnostic_from_error(tks, err, severity)
   local x, y = err.x, err.y
   local err_tk = find_token_at(tks, y, x)
   return {
      range = {
         start = {
            line = y - 1,
            character = x - 1,
         },
         ["end"] = {
            line = y - 1,
            character = (err_tk and x + #err_tk.tk - 1) or x,
         },
      },
      severity = lsp.severity[severity],
      message = err.msg,
   }
end

local function insert_errs(diags, tks, errs, sev)
   for _, err in ipairs(errs or {}) do
      table.insert(diags, make_diagnostic_from_error(tks, err, sev))
   end
end







function Document:type_check_and_publish_result()
   local result = self.result
   if not result then
      util.log("unable to get result of document ", self.uri.path)
      return
   end
   local diags = {}
   if #result.syntax_errors > 0 then
      insert_errs(diags, self.tokens, result.syntax_errors, "Error")
   else
      insert_errs(diags, self.tokens, result.warnings, "Warning")
      insert_errs(diags, self.tokens, result.unknowns, "Error")
      insert_errs(diags, self.tokens, result.type_errors, "Error")
   end
   methods.publish_diagnostics(uri.tostring(self.uri), diags)
end

return document