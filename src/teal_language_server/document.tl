local _module_name = "document"
-- <imports>
local ServerState <const> = require("teal_language_server.server_state")
local Uri <const> = require("teal_language_server.uri")
local lsp <const> = require("teal_language_server.lsp")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local class <const> = require("teal_language_server.class")
local asserts <const> = require("teal_language_server.asserts")
local tracing <const> = require("teal_language_server.tracing")

local ltreesitter <const> = require("ltreesitter")
local teal_parser = ltreesitter.load("./teal.so", "teal")

local tl <const> = require("tl")

-- Token nor tl.Node not exposed :((((
local record Token
   x: integer
   y: integer
   tk: string
   kind: string
end

local interface Node
   kind: string
   x: integer
   y: integer
end

local record Cache
   tokens: {Token}
   err_tokens: {tl.Error}

   ast: {Node}
   parse_errors: {tl.Error}

   result: tl.Result
end

local record Document
   record NodeInfo
      type: string
      source: string
      parent_type: string
      parent_source: string
      preceded_by: string
      self_type: string
      metamethod __tostring: function(NodeInfo): string
   end

   uri: Uri

   _uri: Uri
   _content: string
   _content_lines: {string}
   _version: integer
   _lsp_reader_writer: LspReaderWriter
   _server_state: ServerState
   _cache: Cache
   _tree: ltreesitter.Tree
   _tree_cursor: ltreesitter.Cursor

   metamethod __call: function(self: Document, uri: Uri, content: string, version: integer, lsp_reader_writer: LspReaderWriter, server_state: ServerState): Document
end

local record ArgListNode is Node
    record ArgType
        typename: string
    end

    record ArgInfo
        tk: string
        opt: boolean
        argtype: ArgType
    end

    args: {ArgInfo}
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
   self._tree = teal_parser:parse_string(self._content)
   self._tree_cursor = self._tree:root():create_cursor()
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

local parse_prog = tl.parse_program as function({Token}, {tl.Error}, ?string): {Node}, {string}
function Document:_get_ast(tokens?: {Token}): {Node}, {tl.Error}
   local cache = self._cache
   if not cache.ast then
      local _: any
      cache.parse_errors = {}
      cache.ast, _ = parse_prog(tokens, cache.parse_errors)
      tracing.debug(_module_name, "parse_prog errors: " .. #cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

local type_check <const> = tl.type_check as function({Node}, tl.TypeCheckOptions): tl.Result

function Document:_get_result(ast: {Node}): tl.Result
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

local function _get_node_at(ast: {Node}, y: integer, x: integer): Node
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function Document:get_ast_node_at(type_info: tl.TypeInfo): Node
   if type_info.file == "" then
      return _get_node_at(self:_get_ast(), type_info.y, type_info.x)
   end

   local loaded_file = self._server_state:get_env().loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast as {Node}, type_info.y, type_info.x)
end

function Document:get_function_args_string(type_info: tl.TypeInfo): {string}
   local node = self:get_ast_node_at(type_info) as ArgListNode
   if node == nil then return nil end
   local output: {string} = {}
   for _, arg_info in ipairs(node.args) do
      table.insert(output, arg_info.tk)
   end
   return output
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

   -- update tree and tree cursor as well
   self._tree = teal_parser:parse_string(self._content)
   self._tree_cursor = self._tree:root():create_cursor()
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

function Document:_quick_get(tr: tl.TypeReport, last_token: Token): tl.TypeInfo
   -- this is _really_ hacky... Gotta figure out these weird off by one errors...
   local file = tr.by_pos[self._uri.path]
   if file == nil then
      tracing.warning(_module_name, "selfchecker: the file dissappeared?")
      return nil
   end

   local line = file[last_token.y] or file[last_token.y-1] or file[last_token.y+1]
   if line == nil then
      tracing.warning(_module_name, "selfchecker: the file dissappeared?")
      return nil
   end

   local type_ref = line[last_token.x] or line[last_token.x-1] or line[last_token.x+1]
   if type_ref == nil then
      tracing.warning(_module_name, "selfchecker: couldn't find the typeref")
      return nil
   end
   return self:resolve_type_ref(type_ref)
end

function Document:type_information_for_tokens(tokens: {string}, y: integer, x: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()

   -- try the quick get (works well for self and raw types)
   local type_info: tl.TypeInfo

   -- try and find it in scope
   local scope_symbols <const> = tl.symbols_in_scope(tr, y+1, x+1, self._uri.path)
   if #tokens == 0 then
      local out = {}
      for key, value in pairs(scope_symbols) do out[key] = value end
      for key, value in pairs(tr.globals) do out[key] = value end
      type_info = {
         fields = out
      }
      return type_info
   end
   local type_id <const> = scope_symbols[tokens[1]]
   tracing.warning(_module_name, "tokens[1]: " .. tokens[1])
   if type_id ~= nil then
      type_info = self:resolve_type_ref(type_id)
   end

   -- might be global instead
   if type_info == nil then
      type_info = tr.types[tr.globals[tokens[1]] ]
   end

   if type_info == nil then
      tracing.warning(_module_name, "Unable to find type info in global table as well..")
   end

   tracing.warning(_module_name, "What is this type_info:" .. tostring(type_info))

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         tracing.trace(_module_name, "tokens[i]: " .. tokens[i])

         if type_info.fields then
            type_info = self:resolve_type_ref(type_info.fields[tokens[i]])

         elseif type_info.values and i == #tokens then
            type_info = self:resolve_type_ref(type_info.values)

         -- else
         --    tracing.warning(_module_name, "Something odd is going on here bruv '{}'", type_info)

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

function Document:_parser_token(y: integer, x: integer): Document.NodeInfo
   local moved = self._tree_cursor:goto_first_child()
   local node = self._tree_cursor:current_node()

   if moved == false then
      self._tree_cursor:goto_parent()
      local parent_node = self._tree_cursor:current_node()

      local out: Document.NodeInfo = {
         type = node:type(), 
         source = node:source(), 
         parent_type = parent_node:type(), 
         parent_source = parent_node:source()
      }

      -- for completion
      if node:type() == "." or node:type() == ":" then
         -- considered an error and need to get the previous symbol
         local prev = node:prev_sibling()
         if prev then
            out.preceded_by = prev:source()
         else
            parent_node = parent_node:prev_sibling()
            if parent_node:child_count() > 0 then
               -- no previous symbol, so get parent's previous sibling's last child
               out.preceded_by = parent_node:child(parent_node:child_count()-1):source()
            else
               out.preceded_by = parent_node:source()
            end
         end

      -- for function signature
      elseif node:type() == "(" then
         if parent_node:type() == "arguments" then
            self._tree_cursor:goto_parent()
            local function_call = self._tree_cursor:current_node():child_by_field_name("called_object")
            if function_call then
               out.preceded_by = function_call:source()
            end

         elseif parent_node:type() == "ERROR" then
            for child in parent_node:children() do
               if child:name() == "index" then
                  out.preceded_by = child:source()
                  break
               end
            end
         end
      end

      if out.preceded_by == "self" or 
         out.source:find("self[%.%:]") or 
         out.parent_source:find("self[%.%:]") then
         
         while parent_node:type() ~= "program" do
            self._tree_cursor:goto_parent()
            parent_node = self._tree_cursor:current_node()
            if parent_node:type() == "function_statement" then
               local function_name = parent_node:child_by_field_name("name")
               if function_name then
                  local base_name = function_name:child_by_field_name("base")
                  out.self_type = base_name:source()
                  break
               end
            elseif parent_node:type() == "ERROR" then
               -- for some reason you can't get the node by name in an error state, but you can still iterate over to it
               for child in parent_node:children() do
                  if child:name() == "function_name" then
                     out.self_type = child:child_by_field_name("base"):source()
                     break
                  end
               end
            end
         end

      end

      return out

   end

   local start_point = node:start_point()
   local end_point = node:end_point()

   while moved do
      start_point = node:start_point()
      end_point = node:end_point()

      if y == start_point.row and y == end_point.row then
         if x >= start_point.column and x <= end_point.column then
            return self:_parser_token(y, x)
         end

      elseif y >= start_point.row and y <= end_point.row then
         return self:_parser_token(y, x)
      end

      moved = self._tree_cursor:goto_next_sibling()
      node = self._tree_cursor:current_node()
   end
end

function Document:parser_token(y: integer, x: integer): Document.NodeInfo
   self._tree_cursor:reset(self._tree:root())
   return self:_parser_token(y, x)
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
