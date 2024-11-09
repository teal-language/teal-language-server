local _module_name = "document"
-- <imports>
local ServerState <const> = require("teal_language_server.server_state")
local Uri <const> = require("teal_language_server.uri")
local lsp <const> = require("teal_language_server.lsp")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local class <const> = require("teal_language_server.class")
local asserts <const> = require("teal_language_server.asserts")
local tracing <const> = require("teal_language_server.tracing")

local tl <const> = require("tl")

-- Token nor tl.Node not exposed :((((
local record Token
   x: integer
   y: integer
   tk: string
   kind: string
end

local type Node = any

local record Cache
   tokens: {Token}
   err_tokens: {tl.Error}

   ast: Node
   parse_errors: {tl.Error}

   result: tl.Result
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

function Document:_get_tokens(): {Token}, {tl.Error}
   local cache = self._cache
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self._content, self._uri.path) as ({Token}, {tl.Error})
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

local parse_prog = tl.parse_program as function({Token}, {tl.Error}, ?string): Node, {string}
function Document:_get_ast(tokens: {Token}): Node, {tl.Error}
   local cache = self._cache
   if not cache.ast then
      local _: any
      cache.parse_errors = {}
      cache.ast, _ = parse_prog(tokens, cache.parse_errors)
      tracing.debug(_module_name, "parse_prog errors: " .. #cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check <const> = tl.type_check as function(Node, tl.TypeCheckOptions): tl.Result

function Document:_get_result(ast: Node): tl.Result
   local cache = self._cache
   if not cache.result then
      tracing.info(_module_name, "Type checking document {}", {self._uri.path})
      cache.result = type_check(ast, {
         lax = is_lua(self._uri.path),
         filename = self._uri.path,
         env = self._server_state:get_env(),
      })
   end
   return cache.result
end

function Document:get_type_report(): tl.TypeReport
   local env = self._server_state:get_env()
   return env.reporter:get_report()
end

function Document:clear_cache()
   self._cache = {}
   tracing.debug(_module_name, "Cleared cache for document {}", {self._uri})
end

function Document:update_text(text: string, version: integer)
   tracing.debug(_module_name, "document update_text called (version {})", {version})

   if not version or not self._version or self._version < version then
      self:clear_cache()

      self._content = text
      self._content_lines = nil
      if version then
         self._version = version
      end
   end
end

-- This is slightly modified version of tl.get_token_at
-- that returns the full token (not just the token string)
-- and backtracks to a non-identifier
local function get_token_at(tks: {Token}, y: integer, x: integer): {Token}, boolean
   local output: {Token} = {}
   local ends_with_colon = false
   local i, found = binary_search(
      tks, nil,
      function(tk: Token): boolean
         return tk.y < y or (tk.y == y and tk.x <= x)
      end
   )

   -- so we can properly handle completion with . vs :
   -- Could not remove the pos.character = pos.character - 2 in misc_handler.tl: _on_completion
   -- so just do a lookahead to see if it starts with a colon
   if tks[i+1] and tks[i+1].kind == ":" then ends_with_colon = true end

   if found then
      -- would have to look into how this works for table access via brackets
      while found.kind == "identifier" or found.kind == "." or found.kind == ":" do
         if found.kind == "identifier" then
            table.insert(output, 1, found)
         end
         i = i - 1
         found = tks[i]

         -- if the token is local or global, remove the _next_ token in the list.
         if found.kind == "keyword" and found.tk == "local" or found.tk == "global" then
            table.remove(output, 1)
         end
      end
   end

   return output, ends_with_colon
end

local get_raw_token_at <const> = tl.get_token_at as function({Token}, number, number): string
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

function Document:_publish_diagnostics(diagnostics: {lsp.Diagnostic}, version?: number)
   tracing.debug(_module_name, "Publishing diagnostics for {}...", {self._uri.path})
   self._lsp_reader_writer:send_rpc_notification("textDocument/publishDiagnostics", {
      uri = Uri.tostring(self._uri),
      diagnostics = diagnostics,
      version = version,
   } as lsp.Method.Params)
end

local function imap<V, T>(t: {V}, fn: function(V): (T), start?: integer, finish?: integer): {T}
   local new: {T} = {}
   for i = start or 1, finish or #t do
      new[i] = fn(t[i])
   end
   return new
end

function Document:process_and_publish_results()
   local tks, err_tks = self:_get_tokens()
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

   local ast, parse_errs = self:_get_ast(tks)
   if #parse_errs > 0 then
      self:_publish_diagnostics(imap(parse_errs, function(e: tl.Error): lsp.Diagnostic
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags <const>: {lsp.Diagnostic} = {}
   local fname <const> = self._uri.path
   local result = self:_get_result(ast)

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

function Document:resolve_type_ref(type_number: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()
   local type_info = tr.types[type_number]
   if type_info.ref then
      return self:resolve_type_ref(type_info.ref)
   else
      return type_info
   end
end

function Document:type_information_for_tokens(tokens: {Token}): tl.TypeInfo
   -- only need to get this once
   local tr <const> = self:get_type_report()
   local type_info: tl.TypeInfo

   -- this is _really_ hacky... Gotta figure out these weird off by one errors...
   if tokens[1].tk == "self" then
      local file = tr.by_pos[self._uri.path]
      if file == nil then
         tracing.warning(_module_name, "selfchecker: the file dissappeared?")
         return nil
      end

      local line = file[tokens[1].y] or file[tokens[1].y-1] or file[tokens[1].y+1]
      if line == nil then
         tracing.warning(_module_name, "selfchecker: the line dissappeared?")
         return nil
      end

      local type_ref = line[tokens[1].x] or line[tokens[1].x-1] or line[tokens[1].x+1]
      if type_ref == nil then
         tracing.warning(_module_name, "selfchecker: couldn't find the typeref")
         return nil
      end
      type_info = self:resolve_type_ref(type_ref)
   else
      local scope_symbols <const> = tl.symbols_in_scope(tr, tokens[1].y, tokens[1].x, self._uri.path)
      local type_id <const> = scope_symbols[tokens[1].tk]
      tracing.warning(_module_name, "tokens[1].tk: " .. tokens[1].tk)
      -- could not be found
      if type_id ~= nil then
         type_info = self:resolve_type_ref(type_id)
      end
   end

   -- might be global instead
   if type_info == nil then
      type_info = tr.types[tr.globals[tokens[1].tk]]
   end

   if type_info == nil then
      tracing.warning(_module_name, "Unable to find type info in global table as well..")
   end

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         tracing.trace(_module_name, "tokens[i].tk: " .. tokens[i].tk)

         if type_info.fields then
            type_info = self:resolve_type_ref(type_info.fields[tokens[i].tk])

         elseif type_info.values and i == #tokens then
            type_info = self:resolve_type_ref(type_info.values)

         else
            tracing.warning(_module_name, "Something odd is going on here bruv '{}'", type_info)

         end

         if type_info == nil then break end
      end
   end

   if type_info then
      tracing.trace(_module_name, "Successfully found type info", {})
      return type_info
   end

   tracing.warning(_module_name, "Failed to find type info at given position", {})
   return nil
end

local function indent(n: integer): string
   return ("   "):rep(n)
end
local function ti(list: {string}, ...: string)
   for i = 1, select("#", ...) do
      table.insert(list, (select(i, ...)))
   end
end

function Document:show_type(info: tl.TypeInfo, depth?: integer): string
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

function Document:token_at(where: lsp.Position): {Token}, boolean
   return get_token_at(self:_get_tokens(), where.line + 1, where.character + 1)
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
