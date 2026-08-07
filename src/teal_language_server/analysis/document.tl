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
   record NodeInfo
      -- What the cursor is sitting on, normalized. This is the ONLY thing
      -- handlers should branch on: it is defined here, inside the region that
      -- knows the grammar, so a grammar swap cannot silently change its meaning.
      enum Kind
         "dot"          -- "." -- field access, completion trigger
         "colon"        -- ":" -- method access, completion trigger
         "open_paren"   -- "(" -- signature help trigger
         "identifier"   -- a name: hover, goto-definition, mid-word completion
         "other"        -- anything else; handlers bail
      end
      kind: Kind
      -- `type` and `parent_type` are raw tree-sitter node type names. They change
      -- wholesale if the grammar is swapped, so they are debug/logging detail
      -- only -- never branch on them. Branch on `kind` above.
      type: string
      source: string
      parent_type: string
      parent_source: string
      -- The chain of names ending at the cursor, e.g. {"self", "test_value"} for
      -- a cursor on `test_value` in `self.test_value.other`. Built by walking the
      -- tree, so it stays correct where a node's source text spans more than the
      -- chain does -- feed this to type_information_for_tokens.
      token_chain: {string}      -- a leading `self` resolved to the record name
      token_chain_raw: {string}  -- `self` kept literal, for symbol lookups
      -- the cursor sits in a declaration or type-annotation position, where
      -- offering in-scope completions would be noise
      in_declaration_position: boolean
      preceded_by: string
      self_type: string
      -- the (1-indexed) position to look this request's type up in by_pos:
      -- for completion the preceding expression's result, for signature help the
      -- called object, for hover the identifier under the cursor
      bypos_y: integer
      bypos_x: integer
      -- when the preceding expression is a function call, bypos_(y,x) points at
      -- the *called object* (whose function type stock tl does record) rather than
      -- the call result (a tuple stock tl skips); this holds the number of return
      -- levels to follow to recover the call's result type. Nested calls (f()())
      -- accumulate levels, one rets[1] hop per call.
      bypos_ret_depth: integer
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
-- type_information_for_tokens. (See PR #74 for the tl patch that fixed that case
-- in the checker itself.)
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

   return type_info
end

function Document:type_information_for_tokens(tokens: {string}, y: integer, x: integer): tl.TypeInfo
   local tr <const> = self:get_type_report()

   local type_info: tl.TypeInfo
   -- try and find it in scope
   local scope_symbols <const> = tl.symbols_in_scope(tr, y+1, x+1, self._uri.path)
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
function Document:resolve_preceded_type(node_info: Document.NodeInfo, pos: lsp.Position): tl.TypeInfo
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
-- is declared). Mirrors the backward scope walk in tl.symbols_in_scope, but
-- returns the matched symbol's declaration position instead of its type id.
-- `y`/`x` are 0-indexed (LSP); the returned y/x are 1-indexed (tl convention).
function Document:symbol_declaration_position(name: string, y: integer, x: integer): integer, integer
   local tr <const> = self:get_type_report()
   local symbols = tr.symbols_by_file[self._uri.path]
   if not symbols then
      return nil
   end

   -- Symbols are stored in source order, so the last one whose position is at or
   -- before the cursor is our starting point. (tl uses a binary search here, but
   -- that helper is private to tl, so we scan linearly.)
   local target_y <const> = y + 1
   local target_x <const> = x + 1
   local n = 0
   for i = 1, #symbols do
      local s = symbols[i]
      if s[1] < target_y or (s[1] == target_y and s[2] <= target_x) then
         n = i
      else
         break
      end
   end

   -- Walk backwards, honoring the @{ / @} scope markers, and return the position
   -- of the nearest in-scope declaration matching `name`.
   while n >= 1 do
      local s = symbols[n]
      local symbol_name = s[3]
      if symbol_name == "@{" then
         n = n - 1
      elseif symbol_name == "@}" then
         n = s[4]
      else
         if symbol_name == name then
            return s[1], s[2]
         end
         n = n - 1
      end
   end

   return nil
end

-- ---------------------------------------------------------------------------
-- Everything from here to the end of `_tree_sitter_token` is coupled to the
-- tree-sitter grammar's node type names. Nothing outside this file should
-- compare against a grammar node type; handlers read the normalized flags on
-- NodeInfo instead. Keeping that boundary means swapping the grammar is a
-- change to this file rather than to every handler.
-- ---------------------------------------------------------------------------

local declaration_parent_types <const>: {string:boolean} = {
   ["attnamelist"] = true,  -- `local abc = ...` declarator
   ["attrib"] = true,       -- the `<const>` / `<close>` attribute
   ["nominal"] = true,      -- `local abc: MyType`
   ["basetype"] = true,     -- `local abc: string` / `{string:number}`
   -- deliberately NOT recordkey/parname: tree-sitter-teal did not suppress
   -- completion at a record field name or a parameter name, and widening that
   -- here would be a behaviour change smuggled in under a grammar swap
}

-- Collapse a raw tree-sitter node type into the handler-facing `Kind`. These four
-- tokens happen to be spelled the same in tree-sitter-teal and ts-teal, but that
-- is exactly the assumption worth pinning in one place rather than scattering
-- across the handlers.
local node_kind <const>: {string:Document.NodeInfo.Kind} = {
   ["."] = "dot",
   [":"] = "colon",
   ["("] = "open_paren",
   ["identifier"] = "identifier",
}

local function node_kind_of(node_type: string): Document.NodeInfo.Kind
   return node_kind[node_type] or "other"
end

-- Receiver type named by a `funcname` (the `R` in `function R:m()`).
local function receiver_of(funcname: ltreesitter.Node): string
   local base_name = funcname:child_by_field_name("base")
   return base_name and base_name:source()
end

-- Name of the record `node` declares a method on, if it declares one at all.
-- ts-teal uses a single `stat` node for every kind of statement, so the enclosing
-- function is the one whose `name` field is a `funcname`; statements without one
-- (the `local a = self.` we started from) return nil and the walk continues up.
local function receiver_name(node: ltreesitter.Node): string
   local node_type = node:type()
   if node_type == "stat" then
      local function_name = node:child_by_field_name("name")
      if function_name and function_name:type() == "funcname" then
         return receiver_of(function_name)
      end
   elseif node_type == "ERROR" then
      -- for some reason you can't get the node by name in an error state, but you can still iterate over to it
      --
      -- In a broken parse the children are flattened, so a `funcname` here is not
      -- necessarily a declaration -- a half-typed method *call* (`self:handler(`)
      -- recovers as one too. Only a funcname introduced by the `function` keyword
      -- declares anything; accepting the rest lets call debris shadow the real
      -- enclosing method.
      local declares = false
      for child in node:children() do
         if child:type() == "function" then
            declares = true
         elseif child:name() == "funcname" then
            if declares then
               return receiver_of(child)
            end
         elseif child:name() ~= nil then
            declares = false
         end
      end
   end
   return nil
end

-- ts-teal wraps every expression link in a `prefixexp`, so a node reached via
-- prev_sibling or a field is usually one or more wrappers away from the thing we
-- actually want to dispatch on. Failing to unwrap does not error -- it silently
-- falls through to "the node's own start" and returns a wrong by_pos key.
local function unwrap_prefixexp(node: ltreesitter.Node): ltreesitter.Node
   while node ~= nil and node:type() == "prefixexp" and node:child_count() == 1 do
      node = node:child(0)
   end
   return node
end

-- Position of a child token (1-indexed), or nil if this node has no such child.
local function child_token_position(node: ltreesitter.Node, a: string, b?: string): integer, integer
   for child in node:children() do
      local child_type = child:type()
      if child_type == a or (b ~= nil and child_type == b) then
         local sp = child:start_point()
         return sp.row + 1, sp.column + 1
      end
   end
   return nil
end

-- Append the dotted/method segments of an expression to `out`, left to right.
-- This walks the tree instead of re-lexing source text, which matters because a
-- node's `source` is not always the chain: ts-teal's `functioncall` spans its
-- arguments too, so splitting `self:m(a, b)` on "." and ":" yields a garbage
-- final segment. The spine always yields exactly the names.
local function append_chain_segments(node: ltreesitter.Node, out: {string})
   node = unwrap_prefixexp(node)
   if node == nil then
      return
   end
   local node_type = node:type()
   if node_type == "var" then
      local object = node:child_by_field_name("object")
      if object ~= nil then
         append_chain_segments(object, out)
      end
      local key = node:child_by_field_name("key")
      if key ~= nil then
         table.insert(out, key:source())
      elseif object == nil then
         -- a bare `t`: ts-teal still wraps it in a var, with the name as its
         -- only child rather than as a `key`
         for child in node:children() do
            if child:type() == "identifier" then
               table.insert(out, child:source())
               break
            end
         end
      end
   elseif node_type == "functioncall" then
      append_chain_segments(node:child_by_field_name("called_object"), out)
      local method = node:child_by_field_name("method")
      if method ~= nil then
         table.insert(out, method:source())
      end
   elseif node_type == "identifier" then
      table.insert(out, node:source())
   end
end

-- The token chain ending at the cursor, e.g. {"self", "test_value"} for a cursor
-- on `test_value` in `self.test_value.other`. Anchoring on the leaf's *parent*
-- is what makes it stop at the cursor: the enclosing `var` whose `key` is the
-- leaf spans exactly the prefix, so no truncation pass is needed.
local function token_chain_for(leaf: ltreesitter.Node, parent: ltreesitter.Node): {string}
   local out: {string} = {}
   local parent_type = parent:type()
   if parent_type == "var" or parent_type == "functioncall" then
      append_chain_segments(parent, out)
   elseif parent_type == "funcname" then
      -- flat base/entry/method; take them up to and including the cursor's own
      local leaf_start = leaf:start_point()
      for _, field in ipairs({ "base", "entry", "method" }) do
         local part = parent:child_by_field_name(field)
         if part ~= nil then
            table.insert(out, part:source())
            local part_start = part:start_point()
            if part_start.row == leaf_start.row and part_start.column == leaf_start.column then
               break
            end
         end
      end
   else
      table.insert(out, leaf:source())
   end
   return out
end


-- Map a tree-sitter expression node to the (1-indexed) position where tl records
-- its result type in by_pos, plus the number of return levels to follow so that
-- position holds the callable (rather than the value directly):
--   functioncall  -> the *called object*'s position, ret_depth += 1. tl skips the
--                    call result (a tuple), but records the called object's
--                    function type, whose rets[1] is the result. Nested calls
--                    (f()()) accumulate levels. A method call (`a:b()`) has no
--                    node of its own here, so its ":" is read off the call.
--   var           -> the "."/"[" operator child; the access result lives there
--   anything else -> the node's own start
local function bypos_key_for(node: ltreesitter.Node): integer, integer, integer
   node = unwrap_prefixexp(node)
   if node == nil then
      return nil
   end
   local node_type = node:type()
   if node_type == "functioncall" then
      -- `a:b()` -- ts-teal has no method_index node, the ":" hangs off the call
      -- itself, and that is where tl records the access result.
      if node:child_by_field_name("method") ~= nil then
         local y, x = child_token_position(node, ":")
         if y ~= nil then
            return y, x, 1
         end
      end

      local called = node:child_by_field_name("called_object")
      if called == nil then
         return nil
      end
      -- resolve the called object's by_pos position and add a return level so
      -- the lookup follows the function's first return value; nested calls
      -- accumulate one level per call.
      local y, x, depth = bypos_key_for(called)
      if y == nil then
         return nil
      end
      return y, x, (depth or 0) + 1
   elseif node_type == "var" then
      -- the access result is recorded at the operator: "." for field access,
      -- "[" for bracket indexing
      local y, x = child_token_position(node, ".", "[")
      if y ~= nil then
         return y, x
      end
   end
   local start_point = node:start_point()
   return start_point.row + 1, start_point.column + 1
end

-- Text and by_pos key of the thing being called, for signature help. Under
-- ts-teal `called_object` on a method call holds only the receiver (`s` in
-- `s:rep(`), so the method name has to be stitched back on -- otherwise
-- preceded_by silently degrades from "s:rep" to "s".
local function callee_info(call: ltreesitter.Node): string, integer, integer, integer
   local called = call:child_by_field_name("called_object")
   if called == nil then
      return nil
   end
   local method = call:child_by_field_name("method")
   if method ~= nil then
      local y, x = child_token_position(call, ":")
      return called:source() .. ":" .. method:source(), y, x
   end
   local y, x, depth = bypos_key_for(called)
   return called:source(), y, x, depth
end

function Document:_tree_sitter_token(y: integer, x: integer): Document.NodeInfo
   local moved: boolean = self._tree_cursor:goto_first_child()
   local node = self._tree_cursor:current_node()

   if moved == false then
      self._tree_cursor:goto_parent()

      local parent_node = self._tree_cursor:current_node()

      local parent_type <const> = parent_node:type()

      local out: Document.NodeInfo = {
         kind = node_kind_of(node:type()),
         type = node:type(),
         source = node:source(),
         parent_type = parent_type,
         parent_source = parent_node:source(),
         in_declaration_position = declaration_parent_types[parent_type] == true,
      }

      -- computed before the self_type walk below, which advances the cursor and
      -- reassigns parent_node
      out.token_chain_raw = token_chain_for(node, parent_node)

      -- for completion
      if out.kind == "dot" or out.kind == "colon" then
         -- considered an error and need to get the previous symbol
         local prev = node:prev_sibling()
         if prev == nil then
            -- ERROR recovery can reparent the trigger character, leaving it with
            -- no previous sibling; the symbol is then the last thing under the
            -- parent's previous sibling.
            local sibling = parent_node:prev_sibling()
            if sibling ~= nil then
               prev = sibling:child_count() > 0
                  and sibling:child(sibling:child_count() - 1)
                  or sibling
            end
         end
         if prev ~= nil then
            out.preceded_by = prev:source()
            -- record where the preceding expression's result type lives in by_pos
            -- so completion can resolve it directly (calls, chains, dotted access)
            out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key_for(prev)
         end

      -- for function signature
      elseif out.kind == "open_paren" then
         if parent_type == "args" then
            moved = self._tree_cursor:goto_parent()
            if moved == true then
               out.preceded_by, out.bypos_y, out.bypos_x, out.bypos_ret_depth =
                  callee_info(self._tree_cursor:current_node())
            end

         elseif parent_type == "ERROR" then
            -- An unclosed call (`f(`, `s:rep(`) never becomes a functioncall, so
            -- the callee has to be recovered from the ERROR node's flattened
            -- children. Walk them in order and keep the last callee-shaped run
            -- seen before the "(" -- either `expr` or `expr : name`.
            local callee: ltreesitter.Node
            local method_name: string
            for child in parent_node:children() do
               local child_type = child:type()
               if child_type == "(" then
                  break
               elseif child_type == "prefixexp" or child_type == "var" or child_type == "identifier" then
                  if method_name == nil and callee ~= nil and child_type == "identifier" then
                     -- the name half of `receiver : name`
                     method_name = child:source()
                  else
                     callee, method_name = child, nil
                  end
               end
            end
            if callee ~= nil then
               if method_name ~= nil then
                  out.preceded_by = callee:source() .. ":" .. method_name
                  out.bypos_y, out.bypos_x = child_token_position(parent_node, ":")
               else
                  out.preceded_by = callee:source()
                  out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key_for(callee)
               end
            end
         end

      -- for hover: a cursor sitting on an identifier resolves via by_pos. A field
      -- access (preceded by "." / ":") has its result recorded at the operator,
      -- so look there; a plain variable resolves at its own position.
      elseif out.kind == "identifier" then
         local prev = node:prev_sibling()
         local key_node = (prev and (prev:type() == "." or prev:type() == ":")) and prev or node
         local sp = key_node:start_point()
         out.bypos_y = sp.row + 1
         out.bypos_x = sp.column + 1
      end

      -- `out.source == "self"` matters under ts-teal: in `self.v` the leaf `self`
      -- sits in its own nested `var`, so parent_source is just "self" and the
      -- `self[%.%:]` patterns below never match. Without this the self_type walk
      -- silently stops running for field access on self.
      if out.preceded_by == "self" or
         out.source == "self" or
         out.source:find("self[%.%:]") or
         out.parent_source:find("self[%.%:]") then

         -- The node the cursor sits directly under has to be checked before
         -- ascending: under ts-teal a broken method body (`self:` mid-typing)
         -- puts the funcname in the leaf's *immediate* parent, so a walk that
         -- moves up first would step straight over it.
         while parent_node:type() ~= "chunk" do
            local found = receiver_name(parent_node)
            if found ~= nil then
               out.self_type = found
               break
            end

            moved = self._tree_cursor:goto_parent()
            if moved == false then break end
            parent_node = self._tree_cursor:current_node()
         end

      end

      -- `self` only becomes a usable type name once the enclosing method is
      -- known, so the resolved chain is derived here rather than at build time.
      out.token_chain = out.token_chain_raw
      if out.self_type ~= nil and out.token_chain_raw[1] == "self" then
         out.token_chain = {}
         for i, segment in ipairs(out.token_chain_raw) do
            out.token_chain[i] = i == 1 and out.self_type or segment
         end
      end

      return out

   end

   local start_point = node:start_point()
   local end_point = node:end_point()

   while moved do
      start_point = node:start_point()
      end_point = node:end_point()

      local after_start = y > start_point.row or (y == start_point.row and x >= start_point.column)
      local before_end = y < end_point.row or (y == end_point.row and x < end_point.column)
      if after_start and before_end then
         return self:_tree_sitter_token(y, x)
      end

      moved = self._tree_cursor:goto_next_sibling()
      node = self._tree_cursor:current_node()
   end
end

function Document:tree_sitter_token(y: integer, x: integer): Document.NodeInfo
   self._tree_cursor:reset(self._tree:root())
   return self:_tree_sitter_token(y, x)
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
