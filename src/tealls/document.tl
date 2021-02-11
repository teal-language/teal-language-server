
local tl <const> = require("tl")
local server <const> = require("tealls.server")
local lsp <const> = require("tealls.lsp")
local methods <const> = require("tealls.methods")
local uri <const> = require("tealls.uri")
local util <const> = require("tealls.util")

-- tl.Token nor tl.Node not exposed :((((
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

   type_report: tl.TypeReport
   type_report_env: tl.TypeReportEnv
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
      local res <const>: tl.Result = {
         syntax_errors = {},
         type_errors = {},
         unknowns = {},
         warnings = {},
         env = server:get_env(),
      }
      res.symbol_list = select(4, (tl.type_check as function(Node, tl.TypeCheckOptions): any, any, any, {tl.Symbol})(self.ast, {
         filename = self.uri.path,
         result = res,
         env = res.env,
      })) as {tl.Symbol}
      self.result = res
   elseif key == "type_report" or key == "type_report_env" then
      local res <const> = self.result
      if res then
         self.type_report, self.type_report_env = tl.get_types(res)
      end
   end
   return rawget(self as {string:any}, key)
      or rawget(Document as {string:any}, key)
end

local cache <const>: {string:Document} = {}
local document <const> = {
   Document = Document,
}

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
   self.type_report = nil
   self.type_report_env = nil
end

local function in_range(n: number, base: number, length: number): boolean
   return base <= n and n < base + length
end

local function find_token_at(tks: {Token}, y: number, x: number): number, Token
   return util.binary_search(tks, function(t: Token): number
      return t.y > y and -1
         or t.y < y and 1
         or in_range(x, t.x, #t.tk) and 0
         or t.x > x and -1
         or 1
   end)
end

local function make_diagnostic_from_error(tks: {Token}, err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   local x <const>, y <const> = err.x, err.y
   local _, err_tk <const> = find_token_at(tks, y, x)
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

function Document:type_information_at(where: lsp.Position): tl.TypeInfo
   util.log("getting type report...")
   local tr <const> = self.type_report
   if not tr then
      util.log("   couldn't get type report")
      return
   end
   util.log("   got type report")
   local _, tk <const> = find_token_at(self.tokens, where.line + 1, where.character + 1)
   if not tk then
      return
   end
   util.log("found token: ", tk.tk)
   local symbols <const> = tl.symbols_in_scope(tr, where.line + 1, where.character + 1)
   local type_id <const> = symbols[tk.tk]

   return tr.types[type_id] or tr.types[tr.globals[tk.tk]]
end

local function indent(n: number): string
   return ("   "):rep(n)
end
local function ti(list: {string}, ...: string)
   for i = 1, select("#", ...) do
      table.insert(list, (select(i, ...)))
   end
end
function Document:show_type(info: tl.TypeInfo, depth: number): string
   if not info then return "???" end
   depth = depth or 1
   if depth > 4 then
      return "..."
   end

   local out <const>: {string} = {}

   local function ins(...: string)
      ti(out, ...)
   end

   local function show_record_field(name: string, field_id: number): string
      local field <const> = {}
      ti(field, indent(depth))
      local field_type <const> = self.type_report.types[field_id]
      if field_type.str:match("^type ") then
         ti(field, "type ", name, " = ", (self:show_type(field_type, depth + 1):gsub("^type ", "")))
      else
         ti(field, name, ": ", self:show_type(field_type, depth + 1))
      end
      ti(field, "\n")
      return table.concat(field)
   end

   local function show_record_fields(fields: {string:number})
      if not fields then
         ins("--???\n")
         return
      end
      local fs <const> = {}
      for name, field_id in pairs(fields) do
         ti(fs, show_record_field(name, field_id))
      end
      local function get_name(s: string): string
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(fs, function(a: string, b: string): boolean
         return get_name(a) < get_name(b)
      end)
      for _, f in ipairs(fs) do
         ins(f)
      end
   end

   if info.ref then
      return info.str .. " => " .. self:show_type(self.type_report.types[info.ref], depth + 1)
   elseif info.str == "type record" or info.str == "record" then
      ins(info.str)
      if not info.fields then
         ins(" ??? end")
         return table.concat(out)
      end
      ins("\n")
      show_record_fields(info.fields)
      ins(indent(depth - 1))
      ins("end")
      return table.concat(out)
   elseif info.str == "type enum" then -- an enum def
      ins("enum\n")
      if info.enums then
         for _, str in ipairs(info.enums) do
            ins(indent(depth))
            ins(string.format("%q\n", str))
         end
      else
         ins(indent(depth))
         ins("--???")
      end
      ins(indent(depth - 1))
      ins("end")
      return table.concat(out)
   else
      return info.str
   end
end

function Document:token_at(where: lsp.Position): Token
   local _, tk <const> = find_token_at(self.tokens, where.line + 1, where.character + 1)
   return tk
end

return document

