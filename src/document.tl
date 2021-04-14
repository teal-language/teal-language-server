
local tl <const> = require("tl")
local fs <const> = require("cyan.fs")
local server <const> = require("tealls.server")
local lsp <const> = require("tealls.lsp")
local methods <const> = require("tealls.methods")
local uri <const> = require("tealls.uri")
local util <const> = require("tealls.util")

local cyanutils <const> = require("cyan.util")
local filter <const>, set <const>
   = cyanutils.tab.filter, cyanutils.tab.set

-- tl.Token nor tl.Node not exposed :((((
local record Token
   x: integer
   y: integer
   tk: string
end
local type Node = any

local record Document
   uri: uri.ParsedUri
   text: string
end

local record Cache
   tokens: {Token}
   err_tokens: {Token}

   ast: Node
   parse_errors: {tl.Error}

   result: tl.Result

   type_report: tl.TypeReport
   type_report_env: tl.TypeReportEnv
end

local private_cache <const>: {Document:Cache} = setmetatable({}, {
   __index = function(self: {Document:Cache}, key: Document): Cache
      rawset(self, key, {})
      return rawget(self, key)
   end
})

local function is_lua(fname: string): boolean
   return select(2, fs.extension_split(fname)) == ".lua"
end

function Document:get_tokens(): {Token}, {Token}
   local cache = private_cache[self]
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self.text) as ({Token}, {Token})
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

local parse_prog = tl.parse_program as function({Token}, {tl.Error}): (number, Node)
function Document:get_ast(): Node, {tl.Error}
   local tks, err_tks = self:get_tokens()
   if #err_tks > 0 then
      return
   end

   local cache = private_cache[self]
   if not cache.ast then
      local _: any
      cache.parse_errors = {}
      _, cache.ast = parse_prog(tks, cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check <const> = tl.type_check as function(Node, tl.TypeCheckOptions): tl.Result
function Document:get_result(): tl.Result
   local ast, errs = self:get_ast()
   if #errs > 0 then
      return nil
   end
   local cache = private_cache[self]
   if not cache.result then
      cache.result = type_check(ast, {
         lax = is_lua(self.uri.path),
         filename = self.uri.path,
         env = server:get_env(),
      })
   end
   return cache.result
end

function Document:get_type_report(): tl.TypeReport, tl.TypeReportEnv
   local result = self:get_result()
   if not result then
      return
   end

   local cache = private_cache[self]
   if not cache.type_report then
      cache.type_report, cache.type_report_env = tl.get_types(result)
   end

   return cache.type_report, cache.type_report_env
end

function Document:update_text(text: string)
   private_cache[self] = nil
   self.text = text
end

local cache <const>: {string:Document} = {}
local document <const> = {
   Document = Document,
}

function document.open(u: uri.ParsedUri, content: string): Document
   local d <const> = setmetatable({
      uri = u,
      text = content,
   } as Document, { __index = Document } as metatable<Document>)
   cache[d.uri.path] = d
   return d
end

function document.close(u: uri.ParsedUri)
   cache[u.path] = nil
end

function document.get(u: uri.ParsedUri): Document
   return cache[u.path]
end

local get_token_at <const> = tl.get_token_at as function({Token}, number, number): string

local function make_diagnostic_from_error(tks: {Token}, err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   local x <const>, y <const> = err.x, err.y
   local err_tk <const> = get_token_at(tks, y, x)
   return {
      range = {
         start = {
            line = y - 1,
            character = x - 1,
         },
         ["end"] = {
            line = y - 1,
            character = (err_tk and x + #err_tk - 1) or x,
         },
      },
      severity = lsp.severity[severity],
      message = err.msg,
   }
end

local function insert_errs(fname: string, diags: {lsp.Diagnostic}, tks: {Token}, errs: {tl.Error}, sev: lsp.Severity)
   for _, err in ipairs(errs or {}) do
      if fname == err.filename then
         table.insert(diags, make_diagnostic_from_error(tks, err, sev))
      end
   end
end

--[[ TODO
   We currently start from a fresh environment whenever type checking a document,
   by maintaining a dependency graph and keeping a persistent environment (making
   sure to load and unload modules as they get updated) we could probably speed this up
]]

function Document:process_and_publish_results()
   local tks, err_tks = self:get_tokens()
   local uri_str <const> = uri.tostring(self.uri)
   if #err_tks > 0 then
      methods.publish_diagnostics(uri_str, util.imap(err_tks, function(t: Token): lsp.Diagnostic
         return {
            range = {
               start = lsp.position(t.y - 1, t.x - 1),
               ["end"] = lsp.position(t.y - 1, t.x - 1 + #t.tk),
            },
            severity = lsp.severity.Error,
            message = "Unexpected token",
         }
      end))
      return
   end

   local _, parse_errs = self:get_ast()
   if #parse_errs > 0 then
      methods.publish_diagnostics(uri_str, util.imap(parse_errs, function(e: tl.Error): lsp.Diagnostic
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags <const>: {lsp.Diagnostic} = {}
   local fname <const> = self.uri.path
   local result = self:get_result()
   local disabled_warnings <const> = set(server.config.disable_warnings or {})
   local warning_errors <const> = set(server.config.warning_error or {})
   local enabled_warnings <const> = filter(result.warnings, function(e: tl.Error): boolean
      if is_lua(self.uri.path) then
         return not (disabled_warnings[e.tag]
            or e.msg:find("unknown variable") as boolean)
      else
         return not disabled_warnings[e.tag]
      end
      return
   end)
   local werrors <const>, warnings <const> = filter(enabled_warnings, function(e: tl.Error): boolean
      return warning_errors[e.tag]
   end)
   insert_errs(fname, diags, tks, warnings, "Warning")
   insert_errs(fname, diags, tks, werrors, "Error")
   insert_errs(fname, diags, tks, result.type_errors, "Error")
   methods.publish_diagnostics(uri.tostring(self.uri), diags)
end

function Document:type_information_at(where: lsp.Position): tl.TypeInfo
   local tr <const> = self:get_type_report()
   if not tr then
      return
   end
   local tk <const> = get_token_at(self:get_tokens(), where.line + 1, where.character + 1)
   if not tk then
      return
   end
   local symbols <const> = tl.symbols_in_scope(tr, where.line + 1, where.character + 1)
   local type_id <const> = symbols[tk]

   return tr.types[type_id] or tr.types[tr.globals[tk]]
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

   local tr = self:get_type_report()

   local function show_record_field(name: string, field_id: integer): string
      local field <const> = {}
      ti(field, indent(depth))
      local field_type <const> = tr.types[field_id]
      if field_type.str:match("^type ") then
         ti(field, "type ", name, " = ", (self:show_type(field_type, depth + 1):gsub("^type ", "")))
      else
         ti(field, name, ": ", self:show_type(field_type, depth + 1))
      end
      ti(field, "\n")
      return table.concat(field)
   end

   local function show_record_fields(fields: {string:integer})
      if not fields then
         ins("--???\n")
         return
      end
      local f <const> = {}
      for name, field_id in pairs(fields) do
         ti(f, show_record_field(name, field_id))
      end
      local function get_name(s: string): string
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(f, function(a: string, b: string): boolean
         return get_name(a) < get_name(b)
      end)
      for _, field in ipairs(f) do
         ins(field)
      end
   end

   if info.ref then
      return info.str .. " => " .. self:show_type(tr.types[info.ref], depth + 1)
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
         ins("\n")
      end
      ins(indent(depth - 1))
      ins("end")
      return table.concat(out)
   else
      return info.str
   end
end

function Document:token_at(where: lsp.Position): string
   return get_token_at(self:get_tokens(), where.line + 1, where.character + 1)
end

return document

