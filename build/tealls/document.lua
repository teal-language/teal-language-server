local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local tl = require("tl")
local server = require("tealls.server")
local lsp = require("tealls.lsp")
local methods = require("tealls.methods")
local uri = require("tealls.uri")
local util = require("tealls.util")


local Token = {}




local Node = {}

local Document = {}




local Cache = {}












local private_cache = setmetatable({}, {
   __index = function(self, key)
      rawset(self, key, {})
      return rawget(self, key)
   end,
})

function Document:get_tokens()
   local cache = private_cache[self]
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self.text)
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

local parse_prog = tl.parse_program
function Document:get_ast()
   local tks, err_tks = self:get_tokens()
   if #err_tks > 0 then
      return
   end

   local cache = private_cache[self]
   if not cache.ast then
      local _
      cache.parse_errors = {}
      _, cache.ast = parse_prog(tks, cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check = tl.type_check
function Document:get_result()
   local ast, errs = self:get_ast()
   if #errs > 0 then
      return nil
   end
   local cache = private_cache[self]
   if not cache.result then
      cache.result = {
         syntax_errors = {},
         type_errors = {},
         unknowns = {},
         warnings = {},
         env = server:get_env(),
      }
      local symbols = select(4, type_check(ast, {
         filename = self.uri.path,
         result = cache.result,
         env = cache.result.env,
      }))
      cache.result.symbol_list = symbols
   end
   return cache.result
end

function Document:get_type_report()
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

function Document:update_text(text)
   private_cache[self] = nil
   self.text = text
end

local cache = {}
local document = {
   Document = Document,
}

function document.open(u, content)
   local d = setmetatable({
      uri = u,
      text = content,
   }, { __index = Document })
   cache[d.uri.path] = d
   return d
end

function document.close(u)
   cache[u.path] = nil
end

function document.get(u)
   return cache[u.path]
end

local function in_range(n, base, length)
   return base <= n and n < base + length
end

local function find_token_at(tks, y, x)
   return util.binary_search(tks, function(t)
      return t.y > y and -1 or
      t.y < y and 1 or
      in_range(x, t.x, #t.tk) and 0 or
      t.x > x and -1 or
      1
   end)
end

local function make_diagnostic_from_error(tks, err, severity)
   local x, y = err.x, err.y
   local _, err_tk = find_token_at(tks, y, x)
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

local function insert_errs(fname, diags, tks, errs, sev)
   for _, err in ipairs(errs or {}) do
      if fname == err.filename then
         table.insert(diags, make_diagnostic_from_error(tks, err, sev))
      end
   end
end







function Document:process_and_publish_results()
   local tks, err_tks = self:get_tokens()
   local uri_str = uri.tostring(self.uri)
   if #err_tks > 0 then
      methods.publish_diagnostics(uri_str, util.imap(err_tks, function(t)
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
      methods.publish_diagnostics(uri_str, util.imap(parse_errs, function(e)
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags = {}
   local fname = self.uri.path
   local result = self:get_result()
   if #result.syntax_errors > 0 then
      insert_errs(fname, diags, tks, result.syntax_errors, "Error")
   else
      insert_errs(fname, diags, tks, result.warnings, "Warning")
      insert_errs(fname, diags, tks, result.unknowns, "Error")
      insert_errs(fname, diags, tks, result.type_errors, "Error")
   end
   methods.publish_diagnostics(uri.tostring(self.uri), diags)
end

function Document:type_information_at(where)
   util.log("getting type report...")
   local tr = self:get_type_report()
   if not tr then
      util.log("   couldn't get type report")
      return
   end
   util.log("   got type report")
   local _, tk = find_token_at(self:get_tokens(), where.line + 1, where.character + 1)
   if not tk then
      return
   end
   util.log("found token: ", tk.tk)
   local symbols = tl.symbols_in_scope(tr, where.line + 1, where.character + 1)
   local type_id = symbols[tk.tk]

   return tr.types[type_id] or tr.types[tr.globals[tk.tk]]
end

local function indent(n)
   return ("   "):rep(n)
end
local function ti(list, ...)
   for i = 1, select("#", ...) do
      table.insert(list, (select(i, ...)))
   end
end

function Document:show_type(info, depth)
   if not info then return "???" end
   depth = depth or 1
   if depth > 4 then
      return "..."
   end

   local out = {}

   local function ins(...)
      ti(out, ...)
   end

   local tr = self:get_type_report()

   local function show_record_field(name, field_id)
      local field = {}
      ti(field, indent(depth))
      local field_type = tr.types[field_id]
      if field_type.str:match("^type ") then
         ti(field, "type ", name, " = ", (self:show_type(field_type, depth + 1):gsub("^type ", "")))
      else
         ti(field, name, ": ", self:show_type(field_type, depth + 1))
      end
      ti(field, "\n")
      return table.concat(field)
   end

   local function show_record_fields(fields)
      if not fields then
         ins("--???\n")
         return
      end
      local fs = {}
      for name, field_id in pairs(fields) do
         ti(fs, show_record_field(name, field_id))
      end
      local function get_name(s)
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(fs, function(a, b)
         return get_name(a) < get_name(b)
      end)
      for _, f in ipairs(fs) do
         ins(f)
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
   elseif info.str == "type enum" then
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

function Document:token_at(where)
   local _, tk = find_token_at(self:get_tokens(), where.line + 1, where.character + 1)
   return tk
end

return document