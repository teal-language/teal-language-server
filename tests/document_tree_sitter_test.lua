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
local Document = require("teal_language_server.document")
local ServerState = require("teal_language_server.server_state")

local function doc(content)
   return Document("test-uri", content, 1, {}, ServerState())
end

tested.test("should analyze basic function definitions", function()
   local d = doc([[local function a() end]])

   local node_info = d:tree_sitter_token(0, 2)
   tested.assert({ expected = "local",              actual = node_info.type })
   tested.assert({ expected = "function_statement", actual = node_info.parent_type })

   node_info = d:tree_sitter_token(0, 8)
   tested.assert({ expected = "function", actual = node_info.type })
end)

tested.test("returns nil on empty char", function()
   local d = doc([[local  ]])

   local node_info = d:tree_sitter_token(0, 6)
   tested.assert({ given = "node_info at empty char", should = "be nil", expected = true, actual = node_info == nil })
end)

tested.test("returns program node on empty content", function()
   local d = doc([[]])

   local node_info = d:tree_sitter_token(0, 0)
   tested.assert({ expected = "program", actual = node_info.type })

   node_info = d:tree_sitter_token(0, 6)
   tested.assert({ expected = "program", actual = node_info.type })
end)

tested.test("identifies function calls and vars", function()
   local d = doc([[local dir = require("pl.dir")]])

   local node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "function_call",    actual = node_info.parent_type })

   node_info = d:tree_sitter_token(0, 8)
   tested.assert({ expected = "var",              actual = node_info.parent_type })

   node_info = d:tree_sitter_token(0, 3)
   tested.assert({ expected = "var_declaration",  actual = node_info.parent_type })
end)

tested.test("should recognize when at a .", function()
   local d = doc([[
local dir = require("pl.dir")
dir.
   ]])

   local node_info = d:tree_sitter_token(1, 3)
   tested.assert({ expected = ".",     actual = node_info.type })
   tested.assert({ expected = "ERROR", actual = node_info.parent_type })
   tested.assert({ expected = "dir",   actual = node_info.preceded_by })
end)

tested.test("should recognize when at a :", function()
   local d = doc([[
local t = "fruit"
t:
   ]])

   local node_info = d:tree_sitter_token(1, 1)
   tested.assert({ expected = ":",     actual = node_info.type })
   tested.assert({ expected = "ERROR", actual = node_info.parent_type })
   tested.assert({ expected = "t",     actual = node_info.preceded_by })
end)

tested.test("should recognize a nested .", function()
   local d = doc([[string.byte(t.,]])

   local node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = ".",     actual = node_info.type })
   tested.assert({ expected = "ERROR", actual = node_info.parent_type })
   tested.assert({ expected = "t",     actual = node_info.preceded_by })

   node_info = d:tree_sitter_token(0, 6)
   tested.assert({ expected = ".",      actual = node_info.type })
   tested.assert({ expected = "index",  actual = node_info.parent_type })
   tested.assert({ expected = "string", actual = node_info.preceded_by })
end)

tested.test("should handle chained .", function()
   local d = doc([[lsp.completion_context.]])

   local node_info = d:tree_sitter_token(0, 22)
   tested.assert({ expected = ".",                      actual = node_info.type })
   tested.assert({ expected = "ERROR",                  actual = node_info.parent_type })
   tested.assert({ expected = "lsp.completion_context", actual = node_info.preceded_by })

   node_info = d:tree_sitter_token(0, 19)
   tested.assert({ expected = "identifier",             actual = node_info.type })
   tested.assert({ expected = "index",                  actual = node_info.parent_type })
   tested.assert({ expected = "lsp.completion_context", actual = node_info.parent_source })
   tested.assert({ given = "preceded_by at col 19", should = "be nil", expected = true, actual = node_info.preceded_by == nil })

   node_info = d:tree_sitter_token(0, 3)
   tested.assert({ expected = ".",     actual = node_info.type })
   tested.assert({ expected = "index", actual = node_info.parent_type })
   tested.assert({ expected = "lsp",   actual = node_info.preceded_by })
end)

tested.test("should handle a variable definition", function()
   local d = doc([[local fruit: string = "thing"]])

   local node_info = d:tree_sitter_token(0, 9)
   tested.assert({ expected = "var",   actual = node_info.parent_type })
   tested.assert({ expected = "fruit", actual = node_info.source })

   node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "simple_type", actual = node_info.parent_type })
   tested.assert({ expected = "string",      actual = node_info.source })

   node_info = d:tree_sitter_token(0, 26)
   tested.assert({ expected = "string", actual = node_info.parent_type })
   tested.assert({ expected = "thing",  actual = node_info.source })
end)

tested.test("should handle a basic self function", function()
   local d = doc([[
function Point:move(dx: number, dy: number)
   self.x = self.x + dx
   self.y = self.y + dy
end
   ]])

   local node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = "function_name", actual = node_info.parent_type })
   tested.assert({ expected = "Point",         actual = node_info.source })

   node_info = d:tree_sitter_token(0, 18)
   tested.assert({ expected = "function_name", actual = node_info.parent_type })
   tested.assert({ expected = "move",          actual = node_info.source })

   node_info = d:tree_sitter_token(0, 33)
   tested.assert({ expected = "arg", actual = node_info.parent_type })
   tested.assert({ expected = "dy",  actual = node_info.source })

   node_info = d:tree_sitter_token(2, 6)
   tested.assert({ expected = "index", actual = node_info.parent_type })
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
   tested.assert({ expected = "identifier",              actual = node_info.type })
   tested.assert({ expected = "_something",              actual = node_info.source })
   tested.assert({ expected = "function_name",           actual = node_info.parent_type })
   tested.assert({ expected = "self._something:fruit",   actual = node_info.parent_source })
   tested.assert({ expected = "Document",                actual = node_info.self_type })

   node_info = d:tree_sitter_token(2, 20)
   tested.assert({ expected = "identifier",              actual = node_info.type })
   tested.assert({ expected = "fruit",                   actual = node_info.source })
   tested.assert({ expected = "function_name",           actual = node_info.parent_type })
   tested.assert({ expected = "self._something:fruit",   actual = node_info.parent_source })
   tested.assert({ expected = "Document",                actual = node_info.self_type })

   node_info = d:tree_sitter_token(2, 15)
   tested.assert({ expected = ":",                       actual = node_info.type })
   tested.assert({ expected = ":",                       actual = node_info.source })
   tested.assert({ expected = "function_name",           actual = node_info.parent_type })
   tested.assert({ expected = "self._something:fruit",   actual = node_info.parent_source })
   tested.assert({ expected = "_something",              actual = node_info.preceded_by })
   tested.assert({ expected = "Document",                actual = node_info.self_type })
end)

tested.test("should handle even more nested .'s", function()
   local d = doc([[lsp.orange.depot.box]])

   local node_info = d:tree_sitter_token(0, 6)
   tested.assert({ expected = "identifier",  actual = node_info.type })
   tested.assert({ expected = "orange",      actual = node_info.source })
   tested.assert({ expected = "index",       actual = node_info.parent_type })
   tested.assert({ expected = "lsp.orange",  actual = node_info.parent_source })

   node_info = d:tree_sitter_token(0, 13)
   tested.assert({ expected = "identifier",       actual = node_info.type })
   tested.assert({ expected = "depot",            actual = node_info.source })
   tested.assert({ expected = "index",            actual = node_info.parent_type })
   tested.assert({ expected = "lsp.orange.depot", actual = node_info.parent_source })

   node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = ".",                    actual = node_info.type })
   tested.assert({ expected = ".",                    actual = node_info.source })
   tested.assert({ expected = "index",                actual = node_info.parent_type })
   tested.assert({ expected = "lsp.orange.depot.box", actual = node_info.parent_source })
   tested.assert({ expected = "lsp.orange.depot",     actual = node_info.preceded_by })
end)

tested.test("should handle partial method chains", function()
   local d = doc([[string.byte(t:fruit():,]])

   local node_info = d:tree_sitter_token(0, 21)
   tested.assert({ expected = ":",                        actual = node_info.type })
   tested.assert({ expected = ":",                        actual = node_info.source })
   tested.assert({ expected = "ERROR",                    actual = node_info.parent_type })
   tested.assert({ expected = "string.byte(t:fruit():,",  actual = node_info.parent_source })
   tested.assert({ expected = "t:fruit()",                actual = node_info.preceded_by })
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
   tested.assert({ expected = ":",              actual = node_info.type })
   tested.assert({ expected = ":",              actual = node_info.source })
   tested.assert({ expected = "method_index",   actual = node_info.parent_type })
   tested.assert({ expected = "self",           actual = node_info.preceded_by })
   tested.assert({ expected = "MiscHandlers",   actual = node_info.self_type })
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
   tested.assert({ expected = "identifier",               actual = node_info.type })
   tested.assert({ expected = "params",                   actual = node_info.source })
   tested.assert({ expected = "arg",                      actual = node_info.parent_type })
   tested.assert({ expected = "params:lsp.Method.Params", actual = node_info.parent_source })

   node_info = d:tree_sitter_token(1, 35)
   tested.assert({ expected = "identifier",      actual = node_info.type })
   tested.assert({ expected = "position",        actual = node_info.source })
   tested.assert({ expected = "index",           actual = node_info.parent_type })
   tested.assert({ expected = "params.position", actual = node_info.parent_source })

   node_info = d:tree_sitter_token(2, 35)
   tested.assert({ expected = "identifier",         actual = node_info.type })
   tested.assert({ expected = "_get_node_info",     actual = node_info.source })
   tested.assert({ expected = "method_index",       actual = node_info.parent_type })
   tested.assert({ expected = "self:_get_node_info",actual = node_info.parent_source })
   tested.assert({ expected = "MiscHandlers",       actual = node_info.self_type })

   node_info = d:tree_sitter_token(8, 52)
   tested.assert({ expected = "identifier",    actual = node_info.type })
   tested.assert({ expected = "character",     actual = node_info.source })
   tested.assert({ expected = "index",         actual = node_info.parent_type })
   tested.assert({ expected = "pos.character", actual = node_info.parent_source })
end)

tested.test("should handle getting function signatures with valid syntax", function()
   local d = doc([[tracing.warning()]])

   local node_info = d:tree_sitter_token(0, 15)
   tested.assert({ expected = "(",                actual = node_info.type })
   tested.assert({ expected = "(",                actual = node_info.source })
   tested.assert({ expected = "arguments",        actual = node_info.parent_type })
   tested.assert({ expected = "()",               actual = node_info.parent_source })
   tested.assert({ expected = "tracing.warning",  actual = node_info.preceded_by })
end)

tested.test("should handle getting function signatures with invalid syntax", function()
   local d = doc([[tracing.warning(]])

   local node_info = d:tree_sitter_token(0, 15)
   tested.assert({ expected = "(",                    actual = node_info.type })
   tested.assert({ expected = "(",                    actual = node_info.source })
   tested.assert({ expected = "ERROR",                actual = node_info.parent_type })
   tested.assert({ expected = "tracing.warning(",     actual = node_info.parent_source })
   tested.assert({ expected = "tracing.warning",      actual = node_info.preceded_by })
end)

tested.test("should handle table index access with bracket notation", function()
   local d = doc([[
if indexable_parent_types[node_info.parent_type] then
 tks = split_by_symbols(node_info.parent_source, node_info.self_type)
else
 tks = split_by_symbols(node_info.source, node_info.self_type)
end]])

   local node_info = d:tree_sitter_token(0, 16)
   tested.assert({ expected = "identifier",                                    actual = node_info.type })
   tested.assert({ expected = "indexable_parent_types",                        actual = node_info.source })
   tested.assert({ expected = "index",                                         actual = node_info.parent_type })
   tested.assert({ expected = "indexable_parent_types[node_info.parent_type]", actual = node_info.parent_source })
end)

return tested
