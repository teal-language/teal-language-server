-- Prepend gen/ so we test local source rather than whatever is installed in the luarocks tree
package.path = "gen/?.lua;" .. package.path

-- This fix was found by AI
-- On Windows, "luarocks test" prepends the global luarocks DLL directory
-- (AppData\Roaming\luarocks\...) to package.cpath, but teal.dll lives in the
-- project venv. ltreesitter's dynamic loader calls LoadLibrary on each cpath
-- entry in order; when LoadLibrary returns NULL for a path that doesn't
-- contain teal.dll it crashes (null deref) instead of skipping gracefully.
-- Filter package.cpath to the project venv before document.lua is required,
-- since that module calls ltreesitter.require("teal","teal") at the top level.
-- Note: this is a test-harness-specific problem — real server installs have
-- teal.dll in the first cpath entry luarocks generates, so they don't hit
-- the bad path.
if package.config:sub(1, 1) == "\\" then
    local uv = require("luv")
    local project_dir = uv.cwd():lower()
    local entries = {}
    for path in package.cpath:gmatch("[^;]+") do
        local low = path:lower()
        if low == ".\\?.dll" or low:find(project_dir, 1, true) then
            table.insert(entries, path)
        end
    end
    if #entries > 0 then package.cpath = table.concat(entries, ";") end
end

local tested = require("tested")
local Document = require("teal_language_server.analysis.document")
local ServerState = require("teal_language_server.server_state")

local function doc(content)
   return Document("test-uri", content, 1, {}, ServerState())
end

--
-- Behaviour of the normalized NodeInfo fields.
--
-- These assert what the handlers actually consume -- kind, source,
-- parent_source, token_chain, preceded_by, self_type, in_declaration_position --
-- rather than raw grammar node type names. A ts-teal regeneration that renames
-- or reshapes nodes without changing meaning leaves them green; one that changes
-- meaning breaks them with a message that says what broke.
--
-- Raw `_type` / `_parent_type` are deliberately NOT asserted here. See the
-- canary at the bottom of this file for the one place that pins a raw name, and
-- the comment there for why exactly one is enough.
--

tested.test("a keyword is not something handlers act on", function()
   local d = doc([[local function a() end]])

   local node_info = d:tree_sitter_token(0, 2)
   tested.assert({ expected = "local", actual = node_info.source })
   tested.assert({ expected = "other", actual = node_info.kind })

   node_info = d:tree_sitter_token(0, 8)
   tested.assert({ expected = "function", actual = node_info.source })
   tested.assert({ expected = "other",    actual = node_info.kind })
end)

tested.test("returns nil on empty char", function()
   local d = doc([[local  ]])

   local node_info = d:tree_sitter_token(0, 6)
   tested.assert({ given = "node_info at empty char", should = "be nil", expected = true, actual = node_info == nil })
end)

tested.test("an empty document yields a token at any position", function()
   local d = doc([[]])

   local node_info = d:tree_sitter_token(0, 0)
   tested.assert({ given = "the start of an empty document", should = "not be nil", expected = true, actual = node_info ~= nil })
   tested.assert({ expected = "other", actual = node_info.kind })

   node_info = d:tree_sitter_token(0, 6)
   tested.assert({ given = "a column past the end of an empty document", should = "not be nil", expected = true, actual = node_info ~= nil })
   tested.assert({ expected = "other", actual = node_info.kind })
end)

tested.test("distinguishes a name being declared from a name being called", function()
   local d = doc([[local dir = require("pl.dir")]])

   local node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "identifier", actual = node_info.kind })
   tested.assert({ expected = "require",    actual = node_info.source })
   tested.assert({ expected = false,        actual = node_info.in_declaration_position })

   node_info = d:tree_sitter_token(0, 8)
   tested.assert({ expected = "identifier", actual = node_info.kind })
   tested.assert({ expected = "dir",        actual = node_info.source })
   tested.assert({ expected = true,         actual = node_info.in_declaration_position })

   node_info = d:tree_sitter_token(0, 3)
   tested.assert({ expected = "other", actual = node_info.kind })
   tested.assert({ expected = "local", actual = node_info.source })
end)

tested.test("should recognize when at a .", function()
   local d = doc([[
local dir = require("pl.dir")
dir.
   ]])

   local node_info = d:tree_sitter_token(1, 3)
   tested.assert({ expected = "dot", actual = node_info.kind })
   tested.assert({ expected = "dir", actual = node_info.preceded_by })
end)

tested.test("should recognize when at a :", function()
   local d = doc([[
local t = "fruit"
t:
   ]])

   local node_info = d:tree_sitter_token(1, 1)
   tested.assert({ expected = "colon", actual = node_info.kind })
   tested.assert({ expected = "t",     actual = node_info.preceded_by })
end)

tested.test("should recognize a nested .", function()
   local d = doc([[string.byte(t.,]])

   local node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = "dot", actual = node_info.kind })
   tested.assert({ expected = "t",   actual = node_info.preceded_by })

   node_info = d:tree_sitter_token(0, 6)
   tested.assert({ expected = "dot",    actual = node_info.kind })
   tested.assert({ expected = "string", actual = node_info.preceded_by })
end)

tested.test("should handle chained .", function()
   local d = doc([[lsp.completion_context.]])

   local node_info = d:tree_sitter_token(0, 22)
   tested.assert({ expected = "dot",                    actual = node_info.kind })
   tested.assert({ expected = "lsp.completion_context", actual = node_info.preceded_by })

   node_info = d:tree_sitter_token(0, 19)
   tested.assert({ expected = "identifier",             actual = node_info.kind })
   tested.assert({ expected = "completion_context",     actual = node_info.source })
   tested.assert({ expected = "lsp.completion_context", actual = node_info.parent_source })
   tested.assert({ expected = "lsp.completion_context", actual = table.concat(node_info.token_chain, ".") })
   tested.assert({ given = "preceded_by at col 19", should = "be nil", expected = true, actual = node_info.preceded_by == nil })

   node_info = d:tree_sitter_token(0, 3)
   tested.assert({ expected = "dot", actual = node_info.kind })
   tested.assert({ expected = "lsp", actual = node_info.preceded_by })
end)

tested.test("should handle a variable definition", function()
   local d = doc([[local fruit: string = "thing"]])

   local node_info = d:tree_sitter_token(0, 9)
   tested.assert({ expected = "fruit", actual = node_info.source })
   tested.assert({ expected = true,    actual = node_info.in_declaration_position })

   node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "string", actual = node_info.source })
   tested.assert({ expected = true,     actual = node_info.in_declaration_position })

   node_info = d:tree_sitter_token(0, 26)
   tested.assert({ expected = "thing", actual = node_info.source })
   tested.assert({ expected = "other", actual = node_info.kind })
   tested.assert({ given = "the cursor inside a string literal", should = "not be a declaration", expected = false, actual = node_info.in_declaration_position })
end)

tested.test("should handle a basic self function", function()
   local d = doc([[
function Point:move(dx: number, dy: number)
   self.x = self.x + dx
   self.y = self.y + dy
end
   ]])

   local node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = "identifier", actual = node_info.kind })
   tested.assert({ expected = "Point",      actual = node_info.source })
   tested.assert({ expected = "Point:move", actual = node_info.parent_source })

   node_info = d:tree_sitter_token(0, 18)
   tested.assert({ expected = "move",       actual = node_info.source })
   tested.assert({ expected = "Point:move", actual = node_info.parent_source })
   tested.assert({ expected = "Point.move", actual = table.concat(node_info.token_chain, ".") })

   -- pins the deliberate choice in declaration_parent_types: a parameter name is
   -- NOT treated as a declaration position, matching tree-sitter-teal. Widening
   -- that set would be a behaviour change, so it should not happen by accident.
   node_info = d:tree_sitter_token(0, 33)
   tested.assert({ expected = "dy",  actual = node_info.source })
   tested.assert({ given = "the cursor on a parameter name", should = "not suppress completion", expected = false, actual = node_info.in_declaration_position })

   node_info = d:tree_sitter_token(2, 6)
   tested.assert({ expected = "self",  actual = node_info.source })
   tested.assert({ expected = "Point", actual = node_info.self_type })
end)

tested.test("should resolve self_type through nested function definitions", function()
   local d = doc([[
function Document:thing()
function fruit()
self._something:fruit
end
end
   ]])

   local node_info = d:tree_sitter_token(2, 9)
   tested.assert({ expected = "identifier",            actual = node_info.kind })
   tested.assert({ expected = "_something",            actual = node_info.source })
   tested.assert({ expected = "self._something:fruit", actual = node_info.parent_source })
   tested.assert({ expected = "Document",              actual = node_info.self_type })
   tested.assert({ expected = "Document._something",   actual = table.concat(node_info.token_chain, ".") })
   tested.assert({ expected = "self._something",       actual = table.concat(node_info.token_chain_raw, ".") })

   node_info = d:tree_sitter_token(2, 20)
   tested.assert({ expected = "identifier",                 actual = node_info.kind })
   tested.assert({ expected = "fruit",                      actual = node_info.source })
   tested.assert({ expected = "self._something:fruit",      actual = node_info.parent_source })
   tested.assert({ expected = "Document",                   actual = node_info.self_type })
   tested.assert({ expected = "Document._something.fruit",  actual = table.concat(node_info.token_chain, ".") })

   node_info = d:tree_sitter_token(2, 15)
   tested.assert({ expected = "colon",                 actual = node_info.kind })
   tested.assert({ expected = ":",                     actual = node_info.source })
   tested.assert({ expected = "self._something:fruit", actual = node_info.parent_source })
   tested.assert({ expected = "_something",            actual = node_info.preceded_by })
   tested.assert({ expected = "Document",              actual = node_info.self_type })
end)

tested.test("should handle even more nested .'s", function()
   local d = doc([[lsp.orange.depot.box]])

   local node_info = d:tree_sitter_token(0, 6)
   tested.assert({ expected = "identifier", actual = node_info.kind })
   tested.assert({ expected = "orange",     actual = node_info.source })
   tested.assert({ expected = "lsp.orange", actual = node_info.parent_source })
   tested.assert({ expected = "lsp.orange", actual = table.concat(node_info.token_chain, ".") })

   node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = "identifier",       actual = node_info.kind })
   tested.assert({ expected = "depot",            actual = node_info.source })
   tested.assert({ expected = "lsp.orange.depot", actual = node_info.parent_source })
   tested.assert({ expected = "lsp.orange.depot", actual = table.concat(node_info.token_chain, ".") })

   node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "dot",                   actual = node_info.kind })
   tested.assert({ expected = "lsp.orange.depot.box",  actual = node_info.parent_source })
   tested.assert({ expected = "lsp.orange.depot",      actual = node_info.preceded_by })
end)

tested.test("should handle partial method chains", function()
   local d = doc([[string.byte(t:fruit():,]])

   local node_info = d:tree_sitter_token(0, 21)
   tested.assert({ expected = "colon",       actual = node_info.kind })
   tested.assert({ expected = "t:fruit()",   actual = node_info.preceded_by })
   tested.assert({
      given = "a completion trigger after a call",
      should = "follow one return level to reach the call's result",
      expected = 1,
      actual = node_info.bypos_ret_depth,
   })
end)

tested.test("should handle real code pulling out self", function()
   local d = doc([[
function MiscHandlers:initialize()
   self:_add_handler("initialize", self._on_initialize)
   self:_add_handler("initialized", self._on_initialized)
   self:_add_handler("textDocument/didOpen", self._on_did_open)
   self:_add_handler("textDocument/didClose", self._on_did_close)
   self:_add_handler("textDocument/didSave", self._on_did_save)
   self:_add_handler("textDocument/didChange", self._on_did_change)
   self:_add_handler("textDocument/completion", self._on_completion)
   self:
   -- self:_add_handler("textDocument/signatureHelp", self._on_signature_help)
   -- self:_add_handler("textDocument/definition", self._on_definition)
   -- self:_add_handler("textDocument/hover", self._on_hover)
end
   ]])

   local node_info = d:tree_sitter_token(8, 7)
   tested.assert({ expected = "colon",        actual = node_info.kind })
   tested.assert({ expected = ":",            actual = node_info.source })
   tested.assert({ expected = "self",         actual = node_info.preceded_by })
   tested.assert({ expected = "MiscHandlers", actual = node_info.self_type })
end)

tested.test("should work with more real use cases", function()
   local d = doc([[
function MiscHandlers:_on_hover(params:lsp.Method.Params, id:integer):nil
   local pos <const> = params.position as lsp.Position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, {
         contents = { "Unknown Token:", " Unable to determine what token is under cursor " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character),
         },
      })
      return
   end
end]])

   local node_info = d:tree_sitter_token(0, 35)
   tested.assert({ expected = "identifier",               actual = node_info.kind })
   tested.assert({ expected = "params",                   actual = node_info.source })
   tested.assert({ expected = "params:lsp.Method.Params", actual = node_info.parent_source })

   node_info = d:tree_sitter_token(1, 35)
   tested.assert({ expected = "identifier",      actual = node_info.kind })
   tested.assert({ expected = "position",        actual = node_info.source })
   tested.assert({ expected = "params.position", actual = node_info.parent_source })
   tested.assert({ expected = "params.position", actual = table.concat(node_info.token_chain, ".") })

   node_info = d:tree_sitter_token(2, 35)
   tested.assert({ expected = "identifier",                       actual = node_info.kind })
   tested.assert({ expected = "_get_node_info",                   actual = node_info.source })
   tested.assert({ expected = "self:_get_node_info(params, pos)", actual = node_info.parent_source })
   tested.assert({ expected = "MiscHandlers",                     actual = node_info.self_type })
   tested.assert({ expected = "MiscHandlers._get_node_info",      actual = table.concat(node_info.token_chain, ".") })
   tested.assert({ expected = "self._get_node_info",              actual = table.concat(node_info.token_chain_raw, ".") })

   node_info = d:tree_sitter_token(8, 52)
   tested.assert({ expected = "identifier",    actual = node_info.kind })
   tested.assert({ expected = "character",     actual = node_info.source })
   tested.assert({ expected = "pos.character", actual = node_info.parent_source })
   tested.assert({ expected = "pos.character", actual = table.concat(node_info.token_chain, ".") })
end)

tested.test("should handle getting function signatures with valid syntax", function()
   local d = doc([[tracing.warning()]])

   local node_info = d:tree_sitter_token(0, 15)
   tested.assert({ expected = "open_paren",      actual = node_info.kind })
   tested.assert({ expected = "(",               actual = node_info.source })
   tested.assert({ expected = "tracing.warning", actual = node_info.preceded_by })
end)

tested.test("should handle getting function signatures with invalid syntax", function()
   local d = doc([[tracing.warning(]])

   local node_info = d:tree_sitter_token(0, 15)
   tested.assert({ expected = "open_paren",      actual = node_info.kind })
   tested.assert({ expected = "(",               actual = node_info.source })
   tested.assert({ expected = "tracing.warning", actual = node_info.preceded_by })
end)

tested.test("should handle table index access with bracket notation", function()
   local d = doc([[
if indexable_parent_types[node_info.parent_type] then
 tks = split_by_symbols(node_info.parent_source, node_info.self_type)
else
 tks = split_by_symbols(node_info.source, node_info.self_type)
end]])

   local node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "identifier",             actual = node_info.kind })
   tested.assert({ expected = "indexable_parent_types", actual = node_info.source })
   tested.assert({ expected = "indexable_parent_types", actual = node_info.parent_source })
   tested.assert({ expected = "indexable_parent_types", actual = table.concat(node_info.token_chain, ".") })
end)


--
-- Regression tests for the tree-sitter-teal -> ts-teal migration.
--
-- Every case in this section corresponds to a defect that migration actually
-- introduced, all of which were silent -- nothing crashed, results were just
-- quietly wrong. They assert the NORMALIZED fields (kind, token_chain,
-- self_type, bypos_*) rather than raw grammar node type names, so they survive a
-- future grammar change and keep testing what the handlers consume.
--
-- If you change one of these expectations, check you are not re-introducing the
-- bug named in the test.
--

-- token_chain is built by walking the tree, not by splitting source text. It has
-- to be, because ts-teal's `functioncall` node spans its arguments: splitting
-- `self:handler(p, q)` on "." and ":" yields {"R", "handler(p, q)"}, and that
-- second segment matches nothing in the type report.
tested.test("token chain of a method call excludes its arguments", function()
   local d = doc([[
local record R
   v: number
   handler: function(R, number, number): number
end
function R:m(p: number, q: number)
   local a = self:handler(p, q)
end]])

   local node_info = d:tree_sitter_token(5, 20)
   tested.assert({ expected = "identifier", actual = node_info.kind })
   tested.assert({
      given = "the cursor on the method name of self:handler(p, q)",
      should = "chain to the receiver and method only, without the argument list",
      expected = "R.handler",
      actual = table.concat(node_info.token_chain, "."),
   })
   tested.assert({ expected = "self.handler", actual = table.concat(node_info.token_chain_raw, ".") })
end)

-- A `funcname` is flat, and ts-teal only labels its `entry` field when there is
-- exactly one dotted segment: `a.b.c:d` reports base=a, entry=nil, method=d. A
-- chain built from those three fields therefore drops every middle segment, and
-- the "stop at the cursor" truncation stops working with it -- every position in
-- the name resolves to the same wrong chain rather than to its own prefix.
tested.test("token chain of a dotted function name keeps every segment", function()
   local d = doc([[
function a.b.c:d()
end]])

   local expected = { "a", "a.b", "a.b.c", "a.b.c.d" }
   for i, column in ipairs({ 9, 11, 13, 15 }) do
      local node_info = d:tree_sitter_token(0, column)
      tested.assert({
         given = "the cursor on segment " .. i .. " of the declared name a.b.c:d",
         should = "chain exactly the segments up to and including it",
         expected = expected[i],
         actual = table.concat(node_info.token_chain, "."),
      })
   end
end)

-- ts-teal wraps every expression link in a `prefixexp`. If bypos_key_for fails to
-- unwrap it, dispatch falls through to "the node's own start" and silently
-- returns the wrong by_pos key -- preceded_by still looks right, so only the
-- column reveals it. Here the trigger "." is at column 14, but the type of the
-- preceding `a.b` is recorded at ITS operator, column 12. A fallthrough reports
-- column 11 (the start of `a`) instead.
tested.test("by_pos key of a chained access points at the preceding operator", function()
   local d = doc([[
local a = {b = {c = 1}}
local x = a.b.]])

   local node_info = d:tree_sitter_token(1, 13)
   tested.assert({ expected = "dot",  actual = node_info.kind })
   tested.assert({ expected = "a.b",  actual = node_info.preceded_by })
   tested.assert({ expected = 2,      actual = node_info.bypos_y })
   tested.assert({
      given = "a completion trigger after a chained access",
      should = "resolve at the preceding expression's operator, not its start",
      expected = 12,
      actual = node_info.bypos_x,
   })
end)

-- An unclosed call never becomes a `functioncall`, so the callee is recovered
-- from the flattened ERROR node. ts-teal's `called_object` holds only the
-- receiver, so the method name has to be stitched back on or preceded_by
-- degrades from "s:rep" to "s".
tested.test("unclosed method call keeps the method name", function()
   local d = doc([[
local s = "a"
s:rep(]])

   local node_info = d:tree_sitter_token(1, 5)
   tested.assert({ expected = "open_paren", actual = node_info.kind })
   tested.assert({
      given = "signature help on a half-typed method call",
      should = "report the full receiver:method callee",
      expected = "s:rep",
      actual = node_info.preceded_by,
   })
end)

-- Under ts-teal the leaf `self` in `self.v` sits in its own nested `var`, so
-- parent_source is just "self" and the `self[%.%:]` text patterns never fire.
-- Without an explicit `source == "self"` check the receiver walk stops running.
tested.test("self field access resolves the enclosing record", function()
   local d = doc([[
local record R
   v: number
end
function R:m()
   local a = self.v
end]])

   local node_info = d:tree_sitter_token(4, 14)
   tested.assert({ expected = "self", actual = node_info.source })
   tested.assert({
      given = "the cursor on `self` in a method body",
      should = "resolve self_type to the enclosing record",
      expected = "R",
      actual = node_info.self_type,
   })
   tested.assert({ expected = "R",    actual = table.concat(node_info.token_chain, ".") })
   tested.assert({ expected = "self", actual = table.concat(node_info.token_chain_raw, ".") })
end)

-- In a broken parse the children of an ERROR node are flattened, so a method
-- call on self recovers as a funcname-shaped node sitting between the cursor and
-- the real enclosing declaration. The upward walk must not accept it: only a
-- funcname introduced by the `function` keyword declares anything. Accepting the
-- debris yields the callee's receiver (`self`, or `t` for `t:handler(`) instead
-- of the enclosing record.
--
-- The nesting matters -- a well-formed method body resolves through a different
-- branch entirely and would not exercise this at all.
tested.test("a self method call does not shadow the enclosing record", function()
   local d = doc([[
function Document:initialize()
function inner()
self._handlers:add
end
end]])

   local node_info = d:tree_sitter_token(2, 5)
   tested.assert({ expected = "_handlers", actual = node_info.source })
   tested.assert({
      given = "a self:method() call recovered as funcname debris inside a method",
      should = "resolve self_type to the enclosing record, not the callee's receiver",
      expected = "Document",
      actual = node_info.self_type,
   })
end)

-- With a half-typed `self:`, ts-teal puts the funcname in the leaf's IMMEDIATE
-- parent, so a walk that ascends before checking steps straight over it.
tested.test("receiver is found in the leaf's immediate parent", function()
   local d = doc([[
local record R
   v: number
end
function R:m()
   local a = self:
end]])

   local node_info = d:tree_sitter_token(4, 17)
   tested.assert({ expected = "colon", actual = node_info.kind })
   tested.assert({ expected = "self",  actual = node_info.preceded_by })
   tested.assert({
      given = "a half-typed `self:` in a method body",
      should = "still resolve the enclosing record",
      expected = "R",
      actual = node_info.self_type,
   })
end)

-- Callee recovery in a broken parse has to anchor on the "(" the cursor is
-- actually on. A forward scan from the start of the ERROR node stops at the
-- FIRST paren, so every paren in `f(g(` resolves against `f`.
tested.test("nested unclosed calls resolve the innermost callee", function()
   local d = doc([[
local function f(a: number) end
local function g(b: number) end
f(g(]])

   local outer = d:tree_sitter_token(2, 1)
   tested.assert({ expected = "f", actual = outer.preceded_by })

   local inner = d:tree_sitter_token(2, 3)
   tested.assert({
      given = "the cursor on the inner `(` of f(g(",
      should = "resolve the inner callee, not the outer one",
      expected = "g",
      actual = inner.preceded_by,
   })
end)

tested.test("nested unclosed method calls resolve the innermost callee", function()
   local d = doc([[
local a = {} local b = {}
a:m(b:n(]])

   local inner = d:tree_sitter_token(1, 7)
   tested.assert({
      given = "the cursor on the inner `(` of a:m(b:n(",
      should = "resolve the inner receiver:method",
      expected = "b:n",
      actual = inner.preceded_by,
   })
end)

-- self_type is "the receiver of the enclosing method" -- a property of where the
-- cursor is in the tree, not of what the expression's text happens to spell. A
-- substring test on parent_source makes it fire on `myself.field`, so the answer
-- changes depending on which token of one expression the cursor sits on.
tested.test("self_type does not depend on cursor position within an expression", function()
   local d = doc([[
local record R
  v: number
end
function R:m()
  local myself = {field = 1}
  local z = myself.field
end]])

   local on_receiver = d:tree_sitter_token(5, 12)  -- on `myself`
   local on_field    = d:tree_sitter_token(5, 19)  -- on `field`

   tested.assert({ expected = "myself", actual = on_receiver.source })
   tested.assert({ expected = "field",  actual = on_field.source })
   tested.assert({
      given = "two cursor positions in the same non-self expression",
      should = "agree about self_type",
      expected = tostring(on_receiver.self_type),
      actual = tostring(on_field.self_type),
   })
end)

--
-- Normalized-field coverage. `kind` is the only thing handlers branch on, and
-- nothing tested it before.
--

tested.test("kind normalizes the tokens handlers branch on", function()
   local cases = {
      { kind = "dot",        content = "local a={b=1}\nlocal x = a.b",     y = 1, x = 11 },
      { kind = "colon",      content = "local s=\"a\"\nlocal x = s:rep(2)", y = 1, x = 11 },
      { kind = "open_paren", content = "local function f(a:number) end\nf(1)", y = 1, x = 1 },
      { kind = "identifier", content = "local abc = 1\nprint(abc)",         y = 1, x = 6 },
      { kind = "other",      content = "local abc = 1",                     y = 0, x = 1 },
   }
   for _, case in ipairs(cases) do
      local node_info = doc(case.content):tree_sitter_token(case.y, case.x)
      tested.assert({
         given = "the token at " .. case.y .. "," .. case.x .. " of " .. string.format("%q", case.content),
         should = "have kind " .. case.kind,
         expected = case.kind,
         actual = node_info.kind,
      })
   end
end)

tested.test("in_declaration_position distinguishes naming from referring", function()
   local declaring = doc([[local abc = 1]]):tree_sitter_token(0, 6)
   tested.assert({
      given = "the cursor on the name being declared",
      should = "suppress completion",
      expected = true,
      actual = declaring.in_declaration_position,
   })

   local referring = doc("local a={b=1}\nlocal x = a.b"):tree_sitter_token(1, 12)
   tested.assert({
      given = "the cursor on a field being accessed",
      should = "allow completion",
      expected = false,
      actual = referring.in_declaration_position,
   })

   -- the remaining two entries of declaration_parent_types. Covering them here
   -- rather than by asserting the node type names means the flag stays tested
   -- even if `attrib` / `nominal` are renamed, and stops being tested only if
   -- they stop meaning "the cursor is naming something".
   local attribute = doc([[local x <const> = 1]]):tree_sitter_token(0, 9)
   tested.assert({ expected = "const", actual = attribute.source })
   tested.assert({
      given = "the cursor on a <const> attribute",
      should = "suppress completion",
      expected = true,
      actual = attribute.in_declaration_position,
   })

   local annotation = doc("local record MyType\nend\nlocal a: MyType"):tree_sitter_token(2, 9)
   tested.assert({ expected = "MyType", actual = annotation.source })
   tested.assert({
      given = "the cursor on a named type in an annotation",
      should = "suppress completion",
      expected = true,
      actual = annotation.in_declaration_position,
   })
end)

--
-- Deliberate ts-teal behaviour changes. These differ from tree-sitter-teal and
-- are pinned so a future change to them is a decision rather than drift.
--

-- ts-teal makes builtin type names anonymous tokens, so `string` in a type
-- annotation is no longer an identifier and hover no longer resolves it.
tested.test("a builtin type name is not an identifier", function()
   local node_info = doc([[local a: string = "x"]]):tree_sitter_token(0, 9)
   tested.assert({ expected = "string", actual = node_info.source })
   tested.assert({ expected = "other",  actual = node_info.kind })
   tested.assert({ expected = true,     actual = node_info.in_declaration_position })
end)

-- `chunk` is required to match at least one statement (tree-sitter forbids a rule
-- matching the empty string), so an empty document has no chunk node to return.
-- tree-sitter-teal returned an empty `program` here.
--
-- CANARY: the only test in this file that reaches past the `_` and asserts a raw
-- grammar node type. It is the only one that earns it: every other name
-- node_info.tl dispatches on already has a behavioural test above that fails with
-- a useful message when the grammar shifts under it -- `.`/`:`/`(`/`identifier`
-- via kind, `var`/`object`/`key` and `functioncall`/`called_object`/`method` via
-- token_chain, `stat`/`name`/`funcname`/`base` and `ERROR`/`function` via
-- self_type, `args` via preceded_by, `prefixexp` via bypos_x,
-- `attnamelist`/`attrib`/`nominal`/`basetype` via in_declaration_position.
-- Duplicating those as raw-name assertions would mean a regenerated grammar
-- reports dozens of failures with no way to tell a rename from a real
-- regression. The empty-document shape has no behavioural consequence to hang a
-- test on -- an empty buffer produces no normalized field worth asserting -- so
-- pinning the raw type is the only way to notice it changing.
tested.test("an empty document yields an ERROR root", function()
   local node_info = doc(""):tree_sitter_token(0, 0)
   tested.assert({ expected = "other", actual = node_info.kind })
   tested.assert({ expected = "ERROR", actual = node_info._type })
   tested.assert({ expected = "ERROR", actual = node_info._parent_type })
end)

return tested
