local _module_name = "document_manager"

-- <imports>
local ServerState <const> = require("tea_leaves.server_state")
local LspReaderWriter <const> = require("tea_leaves.lsp_reader_writer")
local Uri <const> = require("tea_leaves.uri")
local Document <const> = require("tea_leaves.document")
local asserts <const> = require("tea_leaves.asserts")
local class <const> = require("tea_leaves.class")

local record DocumentManager
   docs:{string:Document}

   _docs:{string:Document}
   _lsp_reader_writer: LspReaderWriter
   _server_state: ServerState

   metamethod __call: function(self: DocumentManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState): DocumentManager
end

function DocumentManager:__init(lsp_reader_writer: LspReaderWriter, server_state: ServerState)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._docs = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end

function DocumentManager:open(uri: Uri, content: string, version: integer):Document
   asserts.that(self._docs[uri.path] == nil)
   local doc = Document(uri, content, version, self._lsp_reader_writer, self._server_state)
   self._docs[uri.path] = doc
   return doc
end

function DocumentManager:close(uri: Uri)
   asserts.that(self._docs[uri.path] ~= nil)
   self._docs[uri.path] = nil
end

function DocumentManager:get(uri: Uri):Document
   return self._docs[uri.path]
end

class.setup(DocumentManager, "DocumentManager", {
   getters =  {
      docs = function(self:DocumentManager):{string:Document}
         return self._docs
      end
   }
})
return DocumentManager
