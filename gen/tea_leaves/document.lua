local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "document"

local ServerState = require("tea_leaves.server_state")
local Uri = require("tea_leaves.uri")
local lsp = require("tea_leaves.lsp")
local LspReaderWriter = require("tea_leaves.lsp_reader_writer")
local class = require("tea_leaves.class")
local asserts = require("tea_leaves.asserts")
local tracing = require("tea_leaves.tracing")
local util = require("tea_leaves.util")

local tl = require("tl")























local Document = {}













function Document:__init(uri, content, version, lsp_reader_writer, server_state)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._uri = uri
   self._cache = {}
   self._content = content
   self._version = version
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end



local function set(lst)
   local s = {}
   for _, v in ipairs(lst) do
      s[v] = true
   end
   return s
end


local function filter(t, pred)
   local pass = {}
   local fail = {}
   for _, v in ipairs(t) do
      table.insert(pred(v) and pass or fail, v)
   end
   return pass, fail
end

local function binary_search(list, item, cmp)
   local len = #list
   local mid
   local s, e = 1, len
   while s <= e do
      mid = math.floor((s + e) / 2)
      local val = list[mid]
      local res = cmp(val, item)
      if res then
         if mid == len then
            return mid, val
         else
            if not cmp(list[mid + 1], item) then
               return mid, val
            end
         end
         s = mid + 1
      else
         e = mid - 1
      end
   end
end

local function is_lua(fname)
   return fname:sub(-4) == ".lua"
end

function Document:get_tokens()
   local cache = self._cache
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self._content)
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

   local cache = self._cache
   if not cache.ast then
      local _
      cache.parse_errors = {}
      cache.ast, _ = parse_prog(tks, cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check = tl.type_check

function Document:get_result()
   local ast, errs = self:get_ast()
   local found_errors = #errs > 0
   local cache = self._cache
   if not cache.result then
      tracing.info(_module_name, "Type checking document {}", { self._uri.path })
      cache.result = type_check(ast, {
         lax = is_lua(self._uri.path),
         filename = self._uri.path,
         env = self._server_state:get_env(),
      })
   end
   return cache.result, found_errors
end

function Document:get_type_report()
   local result, has_errors = self:get_result()

   local cache = self._cache
   if not cache.type_report then
      cache.type_report, cache.type_report_env = tl.get_types(result)
   end

   return cache.type_report, cache.type_report_env, has_errors
end

local function _strip_trailing_colons(text)

   text = text:gsub(":\n", ":a\n"):gsub(":\r\n", ":a\r\n")
   return text
end

function Document:clear_cache()
   self._cache = {}
   tracing.debug(_module_name, "Cleared cache for document {}", { self._uri })
end

function Document:update_text(text, version)
   tracing.debug(_module_name, "document update_text called (version {})", { version })

   if not version or not self._version or self._version < version then
      self:clear_cache()





      self._content = _strip_trailing_colons(text)

      self._content_lines = nil
      if version then
         self._version = version
      end
   end
end

local get_raw_token_at = tl.get_token_at



local function get_token_at(tks, y, x)
   local _, found = binary_search(
   tks, nil,
   function(tk)
      return tk.y < y or
      (tk.y == y and tk.x <= x)
   end)


   if found and
      found.y == y and
      found.x <= x and x < found.x + #found.tk then

      return found
   end
end

local function make_diagnostic_from_error(tks, err, severity)
   local x, y = err.x, err.y
   local err_tk = get_raw_token_at(tks, y, x)
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

local function insert_errs(fname, diags, tks, errs, sev)
   for _, err in ipairs(errs or {}) do
      if fname == err.filename then
         table.insert(diags, make_diagnostic_from_error(tks, err, sev))
      end
   end
end

function Document:_publish_diagnostics(diagnostics, version)
   tracing.debug(_module_name, "Publishing diagnostics for {}...", { self._uri.path })
   self._lsp_reader_writer:send_rpc_notification("textDocument/publishDiagnostics", {
      uri = Uri.tostring(self._uri),
      diagnostics = diagnostics,
      version = version,
   })
end

local function imap(t, fn, start, finish)
   local new = {}
   for i = start or 1, finish or #t do
      new[i] = fn(t[i])
   end
   return new
end

function Document:process_and_publish_results()
   local tks, err_tks = self:get_tokens()
   if #err_tks > 0 then
      self:_publish_diagnostics(imap(err_tks, function(t)
         return {
            range = {
               start = lsp.position(t.y - 1, t.x - 1),
               ["end"] = lsp.position(t.y - 1, t.x - 1),
            },
            severity = lsp.severity.Error,
            message = "Unexpected token",
         }
      end))
      return
   end

   local _, parse_errs = self:get_ast()
   if #parse_errs > 0 then
      self:_publish_diagnostics(imap(parse_errs, function(e)
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags = {}
   local fname = self._uri.path
   local result, has_errors = self:get_result()
   assert(not has_errors)
   local config = self._server_state.config
   local disabled_warnings = set(config.disable_warnings or {})
   local warning_errors = set(config.warning_error or {})
   local enabled_warnings = filter(result.warnings, function(e)
      if is_lua(self._uri.path) then
         return not (disabled_warnings[e.tag] or
         e.msg:find("unknown variable"))
      else
         return not disabled_warnings[e.tag]
      end
      return
   end)
   local werrors, warnings = filter(enabled_warnings, function(e)
      return warning_errors[e.tag]
   end)
   insert_errs(fname, diags, tks, warnings, "Warning")
   insert_errs(fname, diags, tks, werrors, "Error")
   insert_errs(fname, diags, tks, result.type_errors, "Error")
   self:_publish_diagnostics(diags)
end

function Document:get_type_info_for_symbol(identifier, where)
   local tr, _ = self:get_type_report()
   local symbols = tl.symbols_in_scope(tr, where.line + 1, where.character + 1)
   local type_id = symbols[identifier]
   local result = nil

   if type_id ~= nil then
      result = tr.types[type_id]
   end

   if result == nil then
      result = tr.types[tr.globals[identifier]]
   end

   if result == nil then
      tracing.warning(_module_name, "Failed to find type id for identifier '{}'.  Available symbols: Locals: {}.  Globals: {}", { identifier, symbols, tr.globals })
   else
      tracing.debug(_module_name, "Successfully found type id for given identifier '{}'", { identifier })
   end

   return result
end

function Document:type_information_for_token(token)
   local tr, _ = self:get_type_report()

   local symbols = tl.symbols_in_scope(tr, token.y, token.x)
   local type_id = symbols[token.tk]
   local local_type_info = tr.types[type_id]

   if local_type_info then
      tracing.trace(_module_name, "Successfully found type info by raw token in local scope", {})
      return local_type_info
   end

   local global_type_info = tr.types[tr.globals[token.tk]]

   if global_type_info then
      tracing.trace(_module_name, "Successfully found type info by raw token in globals table", {})
      return global_type_info
   end

   tracing.warning(_module_name, "Failed to find type info at given position", {})
   return nil
end

function Document:type_information_at(where)
   local tr, _ = self:get_type_report()
   local file_info = tr.by_pos[self._uri.path]

   if file_info == nil then
      tracing.warning(_module_name, "Could not find file info for path '{}'", { self._uri.path })
      return nil
   end

   local line_info = file_info[where.line]

   if line_info == nil then
      tracing.warning(_module_name, "Could not find line info for file '{}' at line '{}'", { self._uri.path, where.line })
      return nil
   end

   tracing.trace(_module_name, "Found line info: {}", { line_info })


   local type_id = line_info[where.character] or line_info[where.character - 1] or line_info[where.character + 1]

   if type_id == nil then
      tracing.warning(_module_name, "Could not find type id for file {} at position {}, line info {}", { self._uri.path, where, line_info })
      return nil
   end

   tracing.trace(_module_name, "Successfully found type id {}", { type_id })

   local type_info = tr.types[type_id]

   if type_info == nil then
      tracing.warning(_module_name, "Could not find type info for type id '{}'", { type_id })
      return nil
   end

   tracing.trace(_module_name, "Successfully found type info: {}", { type_info })

   if type_info.str == "string" then

      tracing.trace(_module_name, "Hackily changed type info to string as a special case", {})
      return (self._server_state:get_env().globals["string"])["t"]
   end

   local canonical_type_info = tr.types[type_info.ref]

   if canonical_type_info ~= nil then
      tracing.trace(_module_name, "Successfully found type info from ref field: {}", { canonical_type_info })
      return canonical_type_info
   end

   return type_info
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

   local tr, _ = self:get_type_report()

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
      local f = {}
      for name, field_id in pairs(fields) do
         ti(f, show_record_field(name, field_id))
      end
      local function get_name(s)
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(f, function(a, b)
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

function Document:_get_content_lines()
   if self._content_lines == nil then
      self._content_lines = util.string_split(self._content, "\n")
   end
   return self._content_lines
end

function Document:raw_token_at(where)
   return get_raw_token_at(self:get_tokens(), where.line + 1, where.character + 1)
end

function Document:get_line(line)
   return self:_get_content_lines()[line + 1]
end

function Document:token_at(where)
   return get_token_at(self:get_tokens(), where.line + 1, where.character + 1)
end

class.setup(Document, "Document", {
   getters = {
      uri = function(self)
         return self._uri
      end,
   },
   nilable_members = { '_content_lines' },
})
return Document
