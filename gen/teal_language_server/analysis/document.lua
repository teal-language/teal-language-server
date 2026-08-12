local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "analysis.document"

local ServerState = require("teal_language_server.server_state")
local Uri = require("teal_language_server.util.uri")
local lsp = require("teal_language_server.lsp.protocol")
local LspReaderWriter = require("teal_language_server.lsp.reader_writer")
local class = require("teal_language_server.util.class")
local asserts = require("teal_language_server.util.asserts")
local logging = require("teal_language_server.logging")
local json = require("cjson")

local logger = logging.get_logger(_module_name)

local ltreesitter = require("ltreesitter")
local NodeInfo = require("teal_language_server.analysis.node_info")
local teal_language = ltreesitter.require("ts-teal", "teal")
local teal_parser = teal_language:parser()

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
   self._tree = teal_parser:parse_string(self._content)
   self._tree_cursor = self._tree:root():create_cursor()
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

function Document:_get_ast(tokens)
   local cache = self._cache
   if not cache.ast then
      local _
      cache.parse_errors = {}
      cache.ast, _ = tl.parse_program(tokens, cache.parse_errors, self._uri.path)
      logger:debug("parse_prog errors: %d", #cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

function Document:_get_result(ast)
   local cache = self._cache
   if not cache.result then
      local lax = is_lua(self._uri.path)
      logger:info("Type checking document%s %s", lax and " (lax)" or "", self._uri.path)

      local opts = {
         feat_lax = lax and "on" or "off",
         feat_arity = "on",
      }

      cache.result = tl.check(
      ast, self._uri.path, opts, self._server_state:get_env())
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
   logger:debug("Cleared cache for document %s", self._uri)
end

function Document:update_text(text, version)
   logger:debug("document update_text called (version %s)", version)

   if not version or not self._version or self._version < version then
      self:clear_cache()

      self._content = text
      self._content_lines = nil
      if version then
         self._version = version
      end
   end


   self._tree = teal_parser:parse_string(self._content)
   self._tree_cursor = self._tree:root():create_cursor()
end

local function make_diagnostic_from_error(tks, err, severity)
   local x, y = err.x, err.y
   local err_tk = tl.get_token_at(tks, y, x)
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
   logger:debug("Publishing diagnostics for %s...", self._uri.path)


   setmetatable(diagnostics, json.empty_array_mt)
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
   logger:debug("Detected %d lex errors", #err_tks)
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
   logger:debug("Detected %d parse errors", #parse_errs)
   if #parse_errs > 0 then
      self:_publish_diagnostics(imap(parse_errs, function(e)
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags = {}
   local fname = self._uri.path
   local result = self:_get_result(ast)

   logger:debug("Detected %d type errors", #result.type_errors)

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





local function split_by_symbols(input, self_type, stop_at)
   local t = {}
   if not input then return t end
   for str in string.gmatch(input, "([^%.%:]+)") do
      if str == "self" then
         table.insert(t, self_type)
      else
         table.insert(t, str)
      end
      if stop_at and stop_at == str then
         break
      end
   end
   return t
end














local function scope_walk_start(symbols, y, x)
   local n = 0
   for i = 1, #symbols do
      local s = symbols[i]
      if s[1] < y or (s[1] == y and s[2] <= x) then
         n = i
      else
         break
      end
   end
   if n == #symbols and symbols[n] ~= nil and symbols[n][3] == "@}" then
      n = n - 1
   end
   return n
end






local function visible_symbols(symbols, y, x)
   local visible = {}
   local n = scope_walk_start(symbols, y, x)
   while n >= 1 do
      local s = symbols[n]
      local symbol_name = s[3]
      if symbol_name == "@{" then
         n = n - 1
      elseif symbol_name == "@}" then
         n = s[4]
      else
         if visible[symbol_name] == nil then
            visible[symbol_name] = n
         end
         n = n - 1
      end
   end
   return visible
end

function Document:resolve_type_ref(type_number)
   local tr = self:get_type_report()
   local type_info = tr.types[type_number]
   if type_info and type_info.ref then
      return self:resolve_type_ref(type_info.ref)
   else
      return type_info
   end
end
















function Document:type_information_for_position(y, x, ret_depth)
   local tr = self:get_type_report()
   local file = tr.by_pos[self._uri.path]
   if file == nil or file[y] == nil then
      return nil
   end
   local type_id = file[y][x]
   if type_id == nil then
      return nil
   end
   local type_info = self:resolve_type_ref(type_id)



   for _ = 1, ret_depth or 0 do


      if type_info == nil or
         type_info.t ~= tl.typecodes.FUNCTION or
         type_info.rets == nil or
         type_info.rets[1] == nil then
         return nil
      end
      type_info = self:resolve_type_ref(type_info.rets[1][1])



      if type_info == nil or type_info.t == tl.typecodes.TYPE_VARIABLE then
         return nil
      end
   end

   return type_info
end

function Document:type_information_for_tokens(tokens, y, x)
   local tr = self:get_type_report()

   local type_info

   local symbols = tr.symbols_by_file[self._uri.path] or {}
   local scope_symbols = {}
   for name, index in pairs(visible_symbols(symbols, y + 1, x + 1)) do
      scope_symbols[name] = symbols[index][4]
   end
   logger:trace("Looked up symbols at %d, %d for file %s with result: %s", y + 1, x + 1, self._uri.path, scope_symbols)
   if #tokens == 0 then
      local out = {}
      for key, value in pairs(scope_symbols) do out[key] = value end
      for key, value in pairs(tr.globals) do out[key] = value end
      type_info = {
         fields = out,
      }
      return type_info
   end
   local raw_token = tokens[1]
   logger:trace("Processing token %s (all: %s)", raw_token, tokens)
   local type_id = scope_symbols[raw_token]
   if type_id == nil then
      logger:info("Failed to find type id for token %s", raw_token)
   end
   if type_id ~= nil then
      logger:trace("Matched token %s to type id %s", raw_token, type_id)
      type_info = self:resolve_type_ref(type_id)

      if type_info == nil then
         logger:warning("Failed to resolve type ref for id")
      end
   end


   if type_info == nil then
      type_info = tr.types[tr.globals[raw_token]]

      if type_info == nil then
         logger:info("Unable to find type info in global table as well..")
      end
   end

   logger:debug("Got type info: %s", type_info)

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         logger:trace("tokens[i]: %s", tokens[i])

         if type_info.fields then
            type_info = self:resolve_type_ref(type_info.fields[tokens[i]])

         elseif type_info.values and i == #tokens then
            type_info = self:resolve_type_ref(type_info.values)




         end

         if type_info == nil then break end
      end
   end

   if type_info then
      logger:trace("Successfully found type info")
      return type_info
   end

   logger:info("Failed to find type info at given position")
   return nil
end




function Document:resolve_preceded_type(node_info, pos)
   if node_info.bypos_y then
      local type_info = self:type_information_for_position(node_info.bypos_y, node_info.bypos_x, node_info.bypos_ret_depth)
      if type_info ~= nil then
         logger:debug("Resolved preceded expr via by_pos at %d:%d", node_info.bypos_y, node_info.bypos_x)
         return type_info
      end
   end
   local tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
   logger:debug("Falling back to token chain: %s", tks)
   return self:type_information_for_tokens(tks, pos.line, pos.character)
end





function Document:symbol_declaration_position(name, y, x)
   local tr = self:get_type_report()
   local symbols = tr.symbols_by_file[self._uri.path]
   if not symbols then
      return nil
   end

   local index = visible_symbols(symbols, y + 1, x + 1)[name]
   if index == nil then
      return nil
   end
   return symbols[index][1], symbols[index][2]
end

function Document:tree_sitter_token(y, x)
   self._tree_cursor:reset(self._tree:root())
   return NodeInfo.from_cursor(self._tree_cursor, y, x)
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
