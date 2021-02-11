
local tl <const> = require("tl")
local lsp <const> = require("tealls.lsp")
local methods <const> = require("tealls.methods")
local uri <const> = require("tealls.uri")
local util <const> = require("tealls.util")

-- tl.Token nor tl.Node not exposed
local record Token
   x: number
   y: number
   tk: string
end
local type Node = any

local record Document
   uri: uri.ParsedUri
   text: string

   tokens: {Token}
   syntax_errors: {Token}

   ast: Node
   result: tl.Result

end
;(Document as {string:any}).__index = function(self: Document, key: string): any
   if key == "tokens" or key == "syntax_errors" then
      local tks, errs = tl.lex(self.text) as ({Token}, {Token})
      self.tokens = tks
      self.syntax_errors = errs or {}
   elseif key == "ast" then
      local _: any
      _, self.ast = (tl.parse_program as function({Token}): (number, Node))(self.tokens)
   elseif key == "result" then
      local res <const> = {
         syntax_errors = {},
         type_errors = {},
         unknowns = {},
         warnings = {},
         dependencies = {},
      }
      ;(tl.type_check as function(Node, tl.TypeCheckOptions))(self.ast, {
         filename = self.uri.path,
         result = res,
      })
      self.result = res
   end
   return rawget(self as {string:any}, key)
      or rawget(Document as {string:any}, key)
end

local cache <const>: {string:Document} = {}
local document <const> = {}

function document.open(iden: string | uri.ParsedUri, content: string): Document
   local d <const> = setmetatable({
      uri = iden is string and uri.parse(iden) or iden,
      text = content,
   } as Document, Document as metatable<Document>)
   cache[d.uri.path] = d
   return d
end

function document.close(iden: string | uri.ParsedUri)
   local u <const> = iden is string and uri.parse(iden) or iden
   cache[u.path] = nil
end

function document.get(iden: string | uri.ParsedUri): Document
   local u <const> = iden is string and uri.parse(iden) or iden
   return cache[u.path]
end

function Document:replace_text(text: string)
   self.text = text
   self.tokens = nil
   self.ast = nil
   self.result = nil
end

local function in_range(n: number, base: number, length: number): boolean
   return base <= n and n < base + length
end

local function find_token_at(tks: {Token}, y: number, x: number): Token
   local _, tk <const> = util.binary_search(tks, function(t: Token): number
      return t.y > y and -1
         or t.y < y and 1
         or in_range(x, t.x, #t.tk) and 0
         or t.x > x and -1
         or 1
   end)
   return tk
end

local function make_diagnostic_from_error(tks: {Token}, err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   local x <const>, y <const> = err.x, err.y
   local err_tk <const> = find_token_at(tks, y, x)
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

local function insert_errs(diags: {lsp.Diagnostic}, tks: {Token}, errs: {tl.Error}, sev: lsp.Severity)
   for _, err in ipairs(errs or {}) do
      table.insert(diags, make_diagnostic_from_error(tks, err, sev))
   end
end

--[[ TODO
   We currently start from a fresh environment whenever type checking a document,
   by maintaining a dependency graph and keeping a persistent environment (making
   sure to load and unload modules as they get updated) we could probably speed this up
]]

function Document:type_check_and_publish_result()
   local result <const> = self.result
   if not result then
      util.log("unable to get result of document ", self.uri.path)
      return
   end
   local diags <const>: {lsp.Diagnostic} = {}
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

