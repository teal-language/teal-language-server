local _module_name = "open_document_registry"


local ModuleInfo = require("teal_language_server.module_info")
local ServerState = require("teal_language_server.server_state")
local LspReaderWriter = require("teal_language_server.lsp_reader_writer")
local Uri = require("teal_language_server.uri")
local OpenDocument = require("teal_language_server.open_document")
local asserts = require("teal_language_server.asserts")
local class = require("teal_language_server.class")

local OpenDocumentRegistry = {}









function OpenDocumentRegistry:__init(lsp_reader_writer, server_state)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._docs = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end

function OpenDocumentRegistry:open(file_path, uri, module_info)
   asserts.that(self._docs[file_path] == nil)
   local doc = OpenDocument(uri, self._server_state, module_info)
   self._docs[file_path] = doc
   return doc
end

function OpenDocumentRegistry:close(file_path)
   asserts.that(self._docs[file_path] ~= nil)
   self._docs[file_path] = nil
end

function OpenDocumentRegistry:try_get(file_path)
   return self._docs[file_path]
end

class.setup(OpenDocumentRegistry, "OpenDocumentRegistry", {
   getters = {
      docs = function(self)
         return self._docs
      end,
   },
})
return OpenDocumentRegistry
