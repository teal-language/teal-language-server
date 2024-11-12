local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "document"

local ServerState = require("teal_language_server.server_state")
local Uri = require("teal_language_server.uri")
local lsp = require("teal_language_server.lsp")
local LspReaderWriter = require("teal_language_server.lsp_reader_writer")
local class = require("teal_language_server.class")
local asserts = require("teal_language_server.asserts")
local tracing = require("teal_language_server.tracing")

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

function Document:_get_tokens()
   local cache = self._cache
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self._content, self._uri.path)
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

local parse_prog = tl.parse_program
function Document:_get_ast(tokens)
   local cache = self._cache
   if not cache.ast then
      local _
      cache.parse_errors = {}
      cache.ast, _ = parse_prog(tokens, cache.parse_errors)
      tracing.debug(_module_name, "parse_prog errors: " .. #cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check = tl.type_check

function Document:_get_result(ast)
   local cache = self._cache
   if not cache.result then
      tracing.info(_module_name, "Type checking document {}", { self._uri.path })
      cache.result = type_check(ast, {
         lax = is_lua(self._uri.path),
         filename = self._uri.path,
         env = self._server_state:get_env(),
      })
   end
   return cache.result
end

function Document:get_type_report()
   local env = self._server_state:get_env()
   return env.reporter:get_report()
end

local function _get_node_at(ast, y, x)
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function Document:get_ast_node_at(type_info)
   if type_info.file == "" then
      return _get_node_at(self:_get_ast(), type_info.y, type_info.x)
   end

   local loaded_file = self._server_state:get_env().loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast, type_info.y, type_info.x)
end

function Document:get_function_args_string(type_info)
   local node = self:get_ast_node_at(type_info)
   if node == nil then return nil end
   local output = {}
   for _, arg_info in ipairs(node.args) do
      table.insert(output, arg_info.tk)
   end
   return output
end

function Document:clear_cache()
   self._cache = {}
   tracing.debug(_module_name, "Cleared cache for document {}", { self._uri })
end

function Document:update_text(text, version)
   tracing.debug(_module_name, "document update_text called (version {})", { version })

   if not version or not self._version or self._version < version then
      self:clear_cache()

      self._content = text
      self._content_lines = nil
      if version then
         self._version = version
      end
   end
end




local function get_token_at(tks, y, x)
   local output = {}
   local separators = {}
   local i, found = binary_search(
   tks, nil,
   function(tk)
      return tk.y < y or (tk.y == y and tk.x <= x)
   end)





   if tks[i + 1] and tks[i + 1].kind == ":" then separators[1] = ":" end

   if found then

      while found.kind == "identifier" or found.kind == "." or found.kind == ":" do
         if found.kind == "identifier" then
            table.insert(output, 1, found)
         else
            table.insert(separators, 1, found.kind)
         end
         i = i - 1
         found = tks[i]
      end




      if #separators > 1 and separators[1] == ":" and
         found.kind == "keyword" and found.tk == "local" or found.tk == "global" then
         table.remove(output, 1)
         table.remove(separators, 1)
      end

   end

   return output, separators[#separators] == ":"
end

local get_raw_token_at = tl.get_token_at
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
   local tks, err_tks = self:_get_tokens()
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

   local ast, parse_errs = self:_get_ast(tks)
   if #parse_errs > 0 then
      self:_publish_diagnostics(imap(parse_errs, function(e)
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags = {}
   local fname = self._uri.path
   local result = self:_get_result(ast)

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

function Document:resolve_type_ref(type_number)
   local tr = self:get_type_report()
   local type_info = tr.types[type_number]
   if type_info.ref then
      return self:resolve_type_ref(type_info.ref)
   else
      return type_info
   end
end

function Document:_quick_get(tr, last_token)

   local file = tr.by_pos[self._uri.path]
   if file == nil then
      tracing.warning(_module_name, "selfchecker: the file dissappeared?")
      return nil
   end

   local line = file[last_token.y] or file[last_token.y - 1] or file[last_token.y + 1]
   if line == nil then
      tracing.warning(_module_name, "selfchecker: the file dissappeared?")
      return nil
   end

   local type_ref = line[last_token.x] or line[last_token.x - 1] or line[last_token.x + 1]
   if type_ref == nil then
      tracing.warning(_module_name, "selfchecker: couldn't find the typeref")
      return nil
   end
   return self:resolve_type_ref(type_ref)
end

function Document:type_information_for_tokens(tokens)
   local tr = self:get_type_report()


   local type_info = self:_quick_get(tr, tokens[#tokens])
   if type_info ~= nil then return type_info end


   local scope_symbols = tl.symbols_in_scope(tr, tokens[1].y, tokens[1].x, self._uri.path)
   local type_id = scope_symbols[tokens[1].tk]
   tracing.warning(_module_name, "tokens[1].tk: " .. tokens[1].tk)
   if type_id ~= nil then
      type_info = self:resolve_type_ref(type_id)
   end


   if type_info == nil then
      type_info = tr.types[tr.globals[tokens[1].tk]]
   end

   if type_info == nil then
      tracing.warning(_module_name, "Unable to find type info in global table as well..")
   end

   tracing.warning(_module_name, "What is this type_info:" .. tostring(type_info))

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         tracing.trace(_module_name, "tokens[i].tk: " .. tokens[i].tk)

         if type_info.fields then
            type_info = self:resolve_type_ref(type_info.fields[tokens[i].tk])

         elseif type_info.values and i == #tokens then
            type_info = self:resolve_type_ref(type_info.values)




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

function Document:token_at(where)
   return get_token_at(self:_get_tokens(), where.line + 1, where.character + 1)
end

function Document:raw_token_at(where)
   return get_raw_token_at(self:_get_tokens(), where.line + 1, where.character + 1)
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
