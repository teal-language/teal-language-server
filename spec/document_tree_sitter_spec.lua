local Document = require("teal_language_server.document")
local ServerState = require("teal_language_server.server_state")

describe("tree_sitter_parser", function()
   it("should analyze basic function defintions", function()
      local content = [[local function a() end]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 2)
      assert.same(node_info.type, "local")
      assert.same(node_info.parent_type, "function_statement")

      node_info = doc:tree_sitter_token(0, 8)
      assert.same(node_info.type, "function")
   end)

   it("returns nil on empty char", function()
      local content = [[local  ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 6)
      assert.is_nil(node_info)
   end)

   it("returns on empty content", function()
      local content = [[]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 0)
      assert.same(node_info.type, "program")

      -- and on chars that aren't there yet
      local node_info = doc:tree_sitter_token(0, 6)
      assert.same(node_info.type, "program")
   end)

   it("identifies function calls and vars", function()
      local content = [[local dir = require("pl.dir")]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 16)
      assert.same(node_info.parent_type, "function_call")

      local node_info = doc:tree_sitter_token(0, 8)
      assert.same(node_info.parent_type, "var")

      local node_info = doc:tree_sitter_token(0, 3)
      assert.same(node_info.parent_type, "var_declaration")
   end)

   it("should recognize when at a .", function()
      local content = [[
local dir = require("pl.dir")
dir.
      ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(1, 3)
      assert.same(node_info.type, ".")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.preceded_by, "dir")
   end)

   it("should recognize when at a :", function()
      local content = [[
local t = "fruit"
t:
      ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(1, 1)
      assert.same(node_info.type, ":")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.preceded_by, "t")
   end)

   it("should recognize a nested .", function()
      local content = [[string.byte(t.,]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 13)
      assert.same(node_info.type, ".")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.preceded_by, "t")

      local node_info = doc:tree_sitter_token(0, 6)
      assert.same(node_info.type, ".")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.preceded_by, "string")
   end)

   it("should handle chained .", function()
      local content = [[lsp.completion_context.]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 22)
      assert.same(node_info.type, ".")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.preceded_by, "lsp.completion_context")

      local node_info = doc:tree_sitter_token(0, 19)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "lsp.completion_context")
      assert.is_nil(node_info.preceded_by)

      local node_info = doc:tree_sitter_token(0, 3)
      assert.same(node_info.type, ".")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.preceded_by, "lsp")
   end)

   it("should handle a variable defintion", function()
      local content = [[local fruit: string = "thing"]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 9)
      assert.same(node_info.parent_type, "var")
      assert.same(node_info.source, "fruit")

      local node_info = doc:tree_sitter_token(0, 16)
      assert.same(node_info.parent_type, "simple_type")
      assert.same(node_info.source, "string")

      local node_info = doc:tree_sitter_token(0, 26)
      assert.same(node_info.parent_type, "string")
      assert.same(node_info.source, "thing")
   end)

   it("should handle a basic self function", function()
      local content = [[
function Point:move(dx: number, dy: number)
   self.x = self.x + dx
   self.y = self.y + dy
end
      ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 13)
      assert.same(node_info.parent_type, "function_name")
      assert.same(node_info.source, "Point")

      local node_info = doc:tree_sitter_token(0, 18)
      assert.same(node_info.parent_type, "function_name")
      assert.same(node_info.source, "move")

      local node_info = doc:tree_sitter_token(0, 33)
      assert.same(node_info.parent_type, "arg")
      assert.same(node_info.source, "dy")

      local node_info = doc:tree_sitter_token(2, 6)
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.self_type, "Point")
   end)

   it("", function()
      local content = [[
function Document:thing()
function fruit()
self._something:fruit
end
end
      ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(2, 9)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "_something")
      assert.same(node_info.parent_type, "function_name")
      assert.same(node_info.parent_source, "self._something:fruit")
      assert.same(node_info.self_type, "Document")

      local node_info = doc:tree_sitter_token(2, 20)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "fruit")
      assert.same(node_info.parent_type, "function_name")
      assert.same(node_info.parent_source, "self._something:fruit")
      assert.same(node_info.self_type, "Document")

      local node_info = doc:tree_sitter_token(2, 15)
      assert.same(node_info.type, ":")
      assert.same(node_info.source, ":")
      assert.same(node_info.parent_type, "function_name")
      assert.same(node_info.parent_source, "self._something:fruit")
      assert.same(node_info.preceded_by, "_something")
      assert.same(node_info.self_type, "Document")
   end)

   it("should handle even more nested .'s", function()
      local content = [[lsp.orange.depot.box]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 6)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "orange")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "lsp.orange")

      local node_info = doc:tree_sitter_token(0, 13)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "depot")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "lsp.orange.depot")

      local node_info = doc:tree_sitter_token(0, 16)
      assert.same(node_info.type, ".")
      assert.same(node_info.source, ".")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "lsp.orange.depot.box")
      assert.same(node_info.preceded_by, "lsp.orange.depot")

   end)

   it("should handle partial method chains", function()
      local content = [[string.byte(t:fruit():,]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 21)
      assert.same(node_info.type, ":")
      assert.same(node_info.source, ":")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.parent_source, "string.byte(t:fruit():,")
      assert.same(node_info.preceded_by, "t:fruit()")
   end)

   it("should handle real code pulling out self", function()
      local content = [[
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
      ]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(8, 7)
      assert.same(node_info.type, ":")
      assert.same(node_info.source, ":")
      assert.same(node_info.parent_type, "method_index")
      assert.same(node_info.preceded_by, "self")
      assert.same(node_info.self_type, "MiscHandlers")

   end)


   it("should work with more real use cases", function()
      local content = [[
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
end]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 35)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "params")
      assert.same(node_info.parent_type, "arg")
      assert.same(node_info.parent_source, "params:lsp.Method.Params")

      local node_info = doc:tree_sitter_token(1, 35)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "position")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "params.position")

      local node_info = doc:tree_sitter_token(2, 35)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "_get_node_info")
      assert.same(node_info.parent_type, "method_index")
      assert.same(node_info.parent_source, "self:_get_node_info")
      assert.same(node_info.self_type, "MiscHandlers")

      local node_info = doc:tree_sitter_token(8, 52)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "character")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "pos.character")

   end)

   it("should handle getting function signatures with valid syntax", function()
      local content = [[tracing.warning()]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 15)
      assert.same(node_info.type, "(")
      assert.same(node_info.source, "(")
      assert.same(node_info.parent_type, "arguments")
      assert.same(node_info.parent_source, "()")
      assert.same(node_info.preceded_by, "tracing.warning")
   end)

   it("should handle getting function signatures with invalid syntax", function()
      local content = [[tracing.warning(]]

      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 15)
      assert.same(node_info.type, "(")
      assert.same(node_info.source, "(")
      assert.same(node_info.parent_type, "ERROR")
      assert.same(node_info.parent_source, "tracing.warning(")
      assert.same(node_info.preceded_by, "tracing.warning")
   end)

   it("", function()
      local content = [[
if indexable_parent_types[node_info.parent_type] then
 tks = split_by_symbols(node_info.parent_source, node_info.self_type)
else
 tks = split_by_symbols(node_info.source, node_info.self_type)
end]]
      local doc = Document("test-uri", content, 1, {}, ServerState())

      local node_info = doc:tree_sitter_token(0, 16)
      assert.same(node_info.type, "identifier")
      assert.same(node_info.source, "indexable_parent_types")
      assert.same(node_info.parent_type, "index")
      assert.same(node_info.parent_source, "indexable_parent_types[node_info.parent_type]")
   end)
end)
