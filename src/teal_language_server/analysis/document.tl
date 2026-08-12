local _module_name = "analysis.document"
-- <imports>
local ServerState <const> = require("teal_language_server.server_state")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local class <const> = require("teal_language_server.util.class")
local asserts <const> = require("teal_language_server.util.asserts")
local logging <const> = require("teal_language_server.logging")
local json <const> = require("cjson")

local logger = logging.get_logger(_module_name)

local ltreesitter <const> = require("ltreesitter")
local NodeInfo <const> = require("teal_language_server.analysis.node_info")
local teal_language = ltreesitter.require("ts-teal", "teal")
local teal_parser = teal_language:parser()

local tl <const> = require("tl")

local record Cache
   tokens: {tl.Token}
   err_tokens: {tl.Error}

   ast: tl.Node
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
   _tree: ltreesitter.Tree
   _tree_cursor: ltreesitter.Cursor

   metamethod __call: function(self: Document, uri: Uri, content: string, version: integer, lsp_reader_writer: LspReaderWriter, server_state: ServerState): Document
end

local record ArgListNode is tl.Node
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

function Document:_get_tokens(): {tl.Token}, {tl.Error}
   local cache = self._cache
   if not cache.tokens then
      cache.tokens, cache.err_tokens = tl.lex(self._content, self._uri.path)
      if not cache.err_tokens then
         cache.err_tokens = {}
      end
   end
   return cache.tokens, cache.err_tokens
end

function Document:_get_ast(tokens?: {tl.Token}): tl.Node, {tl.Error}
   local cache = self._cache
   if not cache.ast then
      local _: any
      cache.parse_errors = {}
      cache.ast, _ = tl.parse_program(tokens, cache.parse_errors, self._uri.path)
      logger:debug("parse_prog errors: %d", #cache.parse_errors)
   end
   return cache.ast, cache.parse_errors
end

function Document:_get_result(ast: tl.Node): tl.Result
   local cache = self._cache
   if not cache.result then
      local lax = is_lua(self._uri.path)
      logger:info("Type checking document%s %s", lax and " (lax)" or "", self._uri.path)

      local opts: tl.CheckOptions = {
         feat_lax = lax and "on" or "off",
         feat_arity = "on",
      }

      cache.result = tl.check(
         ast, self._uri.path, opts, self._server_state:get_env())
   end
   return cache.result
end

function Document:get_type_report(): tl.TypeReport
   local env = self._server_state:get_env()
   return env.reporter:get_report()
end

local function _get_node_at(ast: tl.Node, y: integer, x: integer): tl.Node
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function Document:get_ast_node_at(type_info: tl.TypeInfo): tl.Node
   if type_info.file == "" then
      return _get_node_at(self:_get_ast(), type_info.y, type_info.x)
   end

   local loaded_file = self._server_state:get_env().loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast, type_info.y, type_info.x)
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
   logger:debug("Cleared cache for document %s", self._uri)
end

function Document:update_text(text: string, version: integer)
   logger:debug("document update_text called (version %s)", version)

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

local function make_diagnostic_from_error(tks: {tl.Token}, err: tl.Error, severity: lsp.Severity): lsp.Diagnostic
   local x <const>, y <const> = err.x, err.y
   local err_tk <const> = tl.get_token_at(tks, y, x)
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

local function insert_errs(fname: string, diags: {lsp.Diagnostic}, tks: {tl.Token}, errs: {tl.Error}, sev: lsp.Severity)
   for _, err in ipairs(errs or {}) do
      if fname == err.filename then
         table.insert(diags, make_diagnostic_from_error(tks, err, sev))
      end
   end
end

function Document:_publish_diagnostics(diagnostics: {lsp.Diagnostic}, version?: number)
   logger:debug("Publishing diagnostics for %s...", self._uri.path)
   -- cjson encodes an empty table as {} (object) rather than [] (array).
   -- Setting empty_array_mt ensures empty diagnostics serialize as [] per LSP spec.
   setmetatable(diagnostics, json.empty_array_mt as metatable<{lsp.Diagnostic}>)
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
   logger:debug("Detected %d lex errors", #err_tks)
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
   logger:debug("Detected %d parse errors", #parse_errs)
   if #parse_errs > 0 then
      self:_publish_diagnostics(imap(parse_errs, function(e: tl.Error): lsp.Diagnostic
         return make_diagnostic_from_error(tks, e, "Error")
      end))
      return
   end

   local diags <const>: {lsp.Diagnostic} = {}
   local fname <const> = self._uri.path
   local result = self:_get_result(ast)

   logger:debug("Detected %d type errors", #result.type_errors)

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

-- Split a dotted/colon source string (e.g. "self.foo.bar") into a token chain,
-- substituting the enclosing record name for "self". Stops after `stop_at` when
-- given. Pure string parsing over NodeInfo-derived text; feeds
-- type_information_for_tokens.
local function split_by_symbols(input: string, self_type: string, stop_at?: string): {string}
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

-- Index into `symbols` to begin a backward scope walk from, for a 1-indexed
-- cursor at (y, x). Symbols are in source order, so it is the last entry at or
-- before the cursor -- except for the clamp, which is the whole point of this
-- function.
--
-- The final entry is the chunk's closing "@}", and it sits at the end of the
-- last source tl successfully *checked*, which while the user is mid-edit is
-- older than the buffer. Typing anything on a new final line makes the file
-- unparseable, so the report still ends at the previous line and the cursor is
-- past that "@}". Starting there follows its back-pointer over the entire file
-- scope, and every local silently disappears -- completion offers globals only.
-- Backing up one entry gives the top-level scope at end of file, which is the
-- scope a cursor appended to the file is actually in.
local function scope_walk_start(symbols: {tl.TypeReport.Symbol}, y: integer, x: integer): integer
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

-- Innermost visible declaration of every name in scope at a 1-indexed (y, x),
-- as an index into `symbols`. This is tl.symbols_in_scope's walk, kept here so
-- it can start from the clamped index above; one walk serves both callers,
-- since the indexed symbol carries the type id at [4] and its declaration
-- position at [1]/[2].
local function visible_symbols(symbols: {tl.TypeReport.Symbol}, y: integer, x: integer): {string:integer}
   local visible: {string:integer} = {}
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

function Document:resolve_type_ref(type_number: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()
   local type_info = tr.types[type_number]
   if type_info and type_info.ref then
      return self:resolve_type_ref(type_info.ref)
   else
      return type_info
   end
end

-- Resolves the type of an expression directly from its source position via the
-- type report's by_pos map. y/x are 1-indexed (tl convention).
--
-- Stock tl records a single-value result at its position (locals, globals, plain
-- field access), but skips a function call's *result* because it is a tuple. To
-- still resolve a call, callers point y/x at the *called object* (whose function
-- type tl does record) and pass ret_depth = the number of return levels to follow;
-- we then follow the function's first return value (rets[1]) that many times to
-- recover the call's result type. A double call like f()() passes ret_depth=2.
--
-- One case stays unresolvable from the report alone: a generic function whose
-- return is a bare, unconstrained type variable (e.g. `first<T>(...): T`). tl
-- records the declaration-site `T` with no constraint or fields, so following
-- rets yields an empty typevar and we return nil; callers fall back to
-- type_information_for_tokens.
function Document:type_information_for_position(y: integer, x: integer, ret_depth?: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()
   local file = tr.by_pos[self._uri.path]
   if file == nil or file[y] == nil then
      return nil
   end
   local type_id = file[y][x]
   if type_id == nil then
      return nil
   end
   local type_info = self:resolve_type_ref(type_id)

   -- the by_pos entry is the callable itself; follow one rets[1] per call level
   -- (nested calls like f()() need more than one hop).
   for _ = 1, ret_depth or 0 do
      -- not a plain function (e.g. a POLY/overload) or no returns: bail so the
      -- caller falls back to token resolution.
      if type_info == nil
         or type_info.t ~= tl.typecodes.FUNCTION
         or type_info.rets == nil
         or type_info.rets[1] == nil then
         return nil
      end
      type_info = self:resolve_type_ref(type_info.rets[1][1])
      -- a return that resolves to a bare type variable (e.g. generic `T`) carries
      -- no constraint or fields in the report, so it is unusable; treat it as a
      -- miss and let the caller fall back to token resolution
      if type_info == nil or type_info.t == tl.typecodes.TYPE_VARIABLE then
         return nil
      end
   end

   -- resolve_type_ref already followed `ref`, so a nominal still standing here is
   -- one tl never resolved: no ref to chase and no fields to show or index into.
   -- It is a dead end that only renders as `T: T`, so report a miss and
   -- let the caller fall back to name resolution, which can still find the
   -- declaration. See find_type_declaration for why these turn up at all.
   if type_info ~= nil and type_info.t == tl.typecodes.NOMINAL and type_info.fields == nil then
      return nil
   end

   return type_info
end

-- The declaration of a type named `name` in this document, or nil.
--
-- Needed because tl's report leaves type references dangling in two ways, and
-- neither is visible to the scope/global lookups:
--
--   * A nominal only carries a `ref` when the checker actually resolved that
--     reference. In a declaration-only file -- every `.d.tl`, including this
--     project's own `types/` -- annotations are rarely checked against a use, so
--     most nominals arrive ref-less: `ltreesitter.d.tl` holds 17 references to
--     `Cursor` and exactly one of them has a ref.
--   * A record's own name has no by_pos entry at all; the RECORD is recorded at
--     the `record` keyword, a few columns to the left.
--
-- Declarations themselves are in `tr.types` with `str` set to their name, so a
-- same-file scan recovers them. Only an unambiguous match counts: with two
-- same-named declarations in one file there is nothing here to say which one
-- encloses the cursor, and a confidently wrong type is worse than none.
function Document:find_type_declaration(name: string): tl.TypeInfo
   local tr <const> = self:get_type_report()
   local found: tl.TypeInfo
   for _, type_info in pairs(tr.types) do
      if type_info.str == name
         and type_info.file == self._uri.path
         and type_info.t ~= tl.typecodes.NOMINAL then
         if found ~= nil then
            logger:debug("More than one type named %s declared here; not guessing", name)
            return nil
         end
         found = type_info
      end
   end
   return found
end

function Document:type_information_for_tokens(tokens: {string}, y: integer, x: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()

   local type_info: tl.TypeInfo
   -- try and find it in scope
   local symbols <const> = tr.symbols_by_file[self._uri.path] or {}
   local scope_symbols <const>: {string:integer} = {}
   for name, index in pairs(visible_symbols(symbols, y+1, x+1)) do
      scope_symbols[name] = symbols[index][4]
   end
   logger:trace("Looked up symbols at %d, %d for file %s with result: %s", y+1, x+1, self._uri.path, scope_symbols)
   if #tokens == 0 then
      local out = {}
      for key, value in pairs(scope_symbols) do out[key] = value end
      for key, value in pairs(tr.globals) do out[key] = value end
      type_info = {
         fields = out
      }
      return type_info
   end
   local raw_token = tokens[1]
   logger:trace("Processing token %s (all: %s)", raw_token, tokens)
   local type_id <const> = scope_symbols[raw_token]
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

   -- might be global instead
   if type_info == nil then
      type_info = tr.types[tr.globals[raw_token] ]

      if type_info == nil then
         logger:info("Unable to find type info in global table as well..")
      end
   end

   -- last resort: a type declared in this file. Record/enum/interface names are
   -- not scope symbols and not globals, so neither lookup above can ever see
   -- them, which leaves every reference to a locally declared type unresolvable.
   if type_info == nil then
      type_info = self:find_type_declaration(raw_token)
      if type_info == nil then
         logger:info("No type declaration named %s in this file either", raw_token)
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

         -- else
         --    tracing.warning(_module_name, "Something odd is going on here bruv '{}'", type_info)

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

-- Resolve the type of the expression preceding a '.'/':'/'(' trigger. Prefers the
-- direct by_pos lookup (handles calls, method chains, dotted access); on a miss,
-- falls back to re-parsing node_info.preceded_by into a token chain.
function Document:resolve_preceded_type(node_info: NodeInfo, pos: lsp.Position): tl.TypeInfo
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

-- Finds where a symbol named `name` was *declared* (as opposed to where its type
-- is declared): the position of its nearest in-scope declaration, rather than
-- the type id tl.symbols_in_scope would give.
-- `y`/`x` are 0-indexed (LSP); the returned y/x are 1-indexed (tl convention).
function Document:symbol_declaration_position(name: string, y: integer, x: integer): integer, integer
   local tr <const> = self:get_type_report()
   local symbols = tr.symbols_by_file[self._uri.path]
   if not symbols then
      return nil
   end

   local index <const> = visible_symbols(symbols, y+1, x+1)[name]
   if index == nil then
      return nil
   end
   return symbols[index][1], symbols[index][2]
end

function Document:tree_sitter_token(y: integer, x: integer): NodeInfo
   self._tree_cursor:reset(self._tree:root())
   return NodeInfo.from_cursor(self._tree_cursor, y, x)
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
