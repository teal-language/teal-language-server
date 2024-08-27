local _module_name = "document"
-- <imports>
local ServerState <const> = require("tea_leaves.server_state")
local Uri <const> = require("tea_leaves.uri")
local lsp <const> = require("tea_leaves.lsp")
local LspReaderWriter <const> = require("tea_leaves.lsp_reader_writer")
local class <const> = require("tea_leaves.class")
local asserts <const> = require("tea_leaves.asserts")
local tracing <const> = require("tea_leaves.tracing")
local util <const> = require("tea_leaves.util")

local tl <const> = require("tl")

-- Token nor tl.Node not exposed :((((
local record Token
   x: integer
   y: integer
   tk: string
end

local type Node = any

local record Cache
   tokens: {Token}
   err_tokens: {tl.Error}

   ast: Node
   parse_errors: {tl.Error}

   result: tl.Result

   type_report: tl.TypeReport
   type_report_env: tl.TypeReportEnv
end

local record Document
   uri: Uri

   _uri: Uri
   _content: string
   _content_lines: {string}
   _version: integer
   _lsp_reader_writer: LspReaderWriter
   _server_state: ServerState
   _cache: Cache

   metamethod __call: function(self: Document, uri: Uri, content: string, version: integer, lsp_reader_writer: LspReaderWriter, server_state: ServerState): Document
end

function Document:__init(uri: Uri, content: string, version: integer, lsp_reader_writer: LspReaderWriter, server_state: ServerState)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._uri = uri
   self._cache = {}
   self._content = content
   self._version = version
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end

---@desc
--- Create a Set from a list
local function set<Value>(lst: {Value}): {Value:boolean}
   local s <const> = {}
   for _, v in ipairs(lst) do
      s[v] = true
   end
   return s
end

--- Create two new lists from `t`: the values that return `true` from `pred` and the values that return false
local function filter<Value>(t: {Value}, pred: function(Value): boolean): {Value}, {Value}
   local pass <const>: {Value} = {}
   local fail <const>: {Value} = {}
   for _, v in ipairs(t) do
      table.insert(pred(v) and pass or fail, v)
   end
   return pass, fail
end

local function binary_search<T, U>(list: {T}, item: U, cmp: function(T, U): boolean): integer, T
   local len <const> = #list
   local mid: integer
   local s, e = 1, len
   while s <= e do
      mid = math.floor((s + e) / 2)
      local val <const> = list[mid]
      local res <const> = cmp(val, item)
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

local function is_lua(fname: string): boolean
   return fname:sub(-4) == ".lua"
end

function Document:get_tokens(): {Token}, {tl.Error}
   local cache = self._cache
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self._content) as ({Token}, {tl.Error})
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

local parse_prog = tl.parse_program as function({Token}, {tl.Error}, string): Node, {string}
function Document:get_ast(): Node, {tl.Error}
   local tks, err_tks = self:get_tokens()
   if #err_tks > 0 then
      return
   end

   local cache = self._cache
   if not cache.ast then
      local _: any
      cache.parse_errors = {}
      cache.ast, _ = parse_prog(tks, cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check <const> = tl.type_check as function(Node, tl.TypeCheckOptions): tl.Result

function Document:get_result(): tl.Result, boolean
   local ast, errs = self:get_ast()
   local found_errors = #errs > 0
   local cache = self._cache
   if not cache.result then
      tracing.info(_module_name, "Type checking document {}", {self._uri.path})
      cache.result = type_check(ast, {
         lax = is_lua(self._uri.path),
         filename = self._uri.path,
         env = self._server_state:get_env(),
      })
   end
   return cache.result, found_errors
end

function Document:get_type_report(): tl.TypeReport, tl.TypeReportEnv, boolean
   local result, has_errors = self:get_result()

   local cache = self._cache
   if not cache.type_report then
      cache.type_report, cache.type_report_env = tl.get_types(result)
   end

   return cache.type_report, cache.type_report_env, has_errors
end

local function _strip_trailing_colons(text: string): string
   -- TODO - remove this hack
   text = text:gsub(":\n", ":a\n"):gsub(":\r\n", ":a\r\n")
   return text
end

function Document:clear_cache()
   self._cache = {}
   tracing.debug(_module_name, "Cleared cache for document {}", {self._uri})
end

function Document:update_text(text: string, version: integer)
   tracing.debug(_module_name, "document update_text called (version {})", {version})

   if not version or not self._version or self._version < version then
      self:clear_cache()
      -- TODO - this is a hack
      -- necessary since without this, teal fails to parse the line and we can't get any
      -- info from it at all

      -- This helps completion sometimes but also breaks goto labels
      self._content = _strip_trailing_colons(text)
      -- self._content = text
      self._content_lines = nil
      if version then
         self._version = version
      end
   end
end

local get_raw_token_at <const> = tl.get_token_at as function({Token}, number, number): string

-- This is just a copy and pasted version of tl.get_token_at
-- that returns the full token and not just the token string
local function get_token_at(tks: {Token}, y: integer, x: integer): Token
   local _, found <const> = binary_search(
      tks, nil,
      function(tk: Token): boolean
         return tk.y < y
            or (tk.y == y and tk.x <= x)
      end
   )

   if found
      and found.y == y
      and found.x <= x and x < found.x + #found.tk
   then
      return found
   end
end

local function make_diagnostic_from_error(tks: {Token}, err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   local x <const>, y <const> = err.x, err.y
   local err_tk <const> = get_raw_token_at(tks, y, x)
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

function Document:_publish_diagnostics(diagnostics: {lsp.Diagnostic}, version: number)
   tracing.debug(_module_name, "Publishing diagnostics for {}...", {self._uri.path})
   self._lsp_reader_writer:send_rpc_notification("textDocument/publishDiagnostics", {
      uri = Uri.tostring(self._uri),
      diagnostics = diagnostics,
      version = version,
   } as lsp.Method.Params)
end

local function imap<V, T>(t: {V}, fn: function(V): (T), start: integer, finish: integer): {T}
   local new: {T} = {}
   for i = start or 1, finish or #t do
      new[i] = fn(t[i])
   end
   return new
end

function Document:process_and_publish_results()
   local tks, err_tks = self:get_tokens()
   if #err_tks > 0 then
      self:_publish_diagnostics(imap(err_tks, function(t: tl.Error): lsp.Diagnostic
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
      self:_publish_diagnostics(imap(parse_errs, function(e: tl.Error): lsp.Diagnostic
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags <const>: {lsp.Diagnostic} = {}
   local fname <const> = self._uri.path
   local result, has_errors = self:get_result()
   assert(not has_errors)
   local config = self._server_state.config
   local disabled_warnings <const> = set(config.disable_warnings or {})
   local warning_errors <const> = set(config.warning_error or {})
   local enabled_warnings <const> = filter(result.warnings, function(e: tl.Error): boolean
      if is_lua(self._uri.path) then
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
   self:_publish_diagnostics(diags)
end

function Document:get_type_info_for_symbol(identifier:string, where: lsp.Position): tl.TypeInfo
   local tr <const>, _ = self:get_type_report()
   local symbols = tl.symbols_in_scope(tr, where.line + 1, where.character + 1)
   local type_id <const> = symbols[identifier]
   local result:tl.TypeInfo = nil

   if type_id ~= nil then
      result = tr.types[type_id]
   end

   if result == nil then
      result = tr.types[tr.globals[identifier]]
   end

   if result == nil then
      tracing.warning(_module_name, "Failed to find type id for identifier '{}'.  Available symbols: Locals: {}.  Globals: {}", {identifier, symbols, tr.globals})
   else
      tracing.debug(_module_name, "Successfully found type id for given identifier '{}'", {identifier})
   end

   return result
end

function Document:type_information_for_token(token: Token): tl.TypeInfo
   local tr <const>, _ = self:get_type_report()

   local symbols <const> = tl.symbols_in_scope(tr, token.y, token.x)
   local type_id <const> = symbols[token.tk]
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

function Document:type_information_at(where: lsp.Position): tl.TypeInfo
   local tr <const>, _ = self:get_type_report()
   local file_info = tr.by_pos[self._uri.path]

   if file_info == nil then
      tracing.warning(_module_name, "Could not find file info for path '{}'", {self._uri.path})
      return nil
   end

   local line_info = file_info[where.line]

   if line_info == nil then
      tracing.warning(_module_name, "Could not find line info for file '{}' at line '{}'", {self._uri.path, where.line})
      return nil
   end

   tracing.trace(_module_name, "Found line info: {}", {line_info})
   -- I don't know why we have to check character, character-1, and character+1 here
   -- TODO - figure out why line_info and where.character are off by one sometimes
   local type_id = line_info[where.character] or line_info[where.character-1] or line_info[where.character+1]

   if type_id == nil then
      tracing.warning(_module_name, "Could not find type id for file {} at position {}, line info {}", {self._uri.path, where, line_info})
      return nil
   end

   tracing.trace(_module_name, "Successfully found type id {}", {type_id})

   local type_info = tr.types[type_id]

   if type_info == nil then
      tracing.warning(_module_name, "Could not find type info for type id '{}'", {type_id})
      return nil
   end

   tracing.trace(_module_name, "Successfully found type info: {}", {type_info})

   if type_info.str == "string" then
      -- TODO - why is this necessary in order to get string deref vars?
      tracing.trace(_module_name, "Hackily changed type info to string as a special case", {})
      return (self._server_state:get_env().globals["string"] as {string:tl.TypeInfo})["t"]
   end

   local canonical_type_info = tr.types[type_info.ref]

   if canonical_type_info ~= nil then
      tracing.trace(_module_name, "Successfully found type info from ref field: {}", {canonical_type_info})
      return canonical_type_info
   end

   return type_info
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

   local tr, _ = self:get_type_report()

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

function Document:_get_content_lines(): {string}
   if self._content_lines == nil then
      self._content_lines = util.string_split(self._content, "\n")
   end
   return self._content_lines
end

function Document:raw_token_at(where: lsp.Position): string
   return get_raw_token_at(self:get_tokens(), where.line + 1, where.character + 1)
end

function Document:get_line(line: integer): string
   return self:_get_content_lines()[line + 1]
end

function Document:token_at(where: lsp.Position): Token
   return get_token_at(self:get_tokens(), where.line + 1, where.character + 1)
end

class.setup(Document, "Document", {
   getters =  {
      uri = function(self:Document):Uri
         return self._uri
      end
   },
   nilable_members = { '_content_lines' },
})
return Document
