local _module_name = "document_manager"


local ServerState = require("tea_leaves.server_state")
local LspReaderWriter = require("tea_leaves.lsp_reader_writer")
local Uri = require("tea_leaves.uri")
local Document = require("tea_leaves.document")
local asserts = require("tea_leaves.asserts")
local class = require("tea_leaves.class")

local DocumentManager = {}









function DocumentManager:__init(lsp_reader_writer, server_state)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._docs = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end

function DocumentManager:open(uri, content, version)
   asserts.that(self._docs[uri.path] == nil)
   local doc = Document(uri, content, version, self._lsp_reader_writer, self._server_state)
   self._docs[uri.path] = doc
   return doc
end

function DocumentManager:close(uri)
   asserts.that(self._docs[uri.path] ~= nil)
   self._docs[uri.path] = nil
end

function DocumentManager:get(uri)
   return self._docs[uri.path]
end

class.setup(DocumentManager, "DocumentManager", {
   getters = {
      docs = function(self)
         return self._docs
      end,
   },
})
return DocumentManager
