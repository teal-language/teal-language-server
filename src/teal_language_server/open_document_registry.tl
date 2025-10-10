local _module_name = "open_document_registry"

-- <imports>
local ModuleInfo <const> = require("teal_language_server.module_info")
local ServerState <const> = require("teal_language_server.server_state")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local Uri <const> = require("teal_language_server.uri")
local OpenDocument <const> = require("teal_language_server.open_document")
local asserts <const> = require("teal_language_server.asserts")
local class <const> = require("teal_language_server.class")

local record OpenDocumentRegistry
   docs:{string:OpenDocument}

   _docs:{string:OpenDocument}
   _lsp_reader_writer: LspReaderWriter
   _server_state: ServerState

   metamethod __call: function(self: OpenDocumentRegistry, lsp_reader_writer: LspReaderWriter, server_state: ServerState): OpenDocumentRegistry
end

function OpenDocumentRegistry:__init(lsp_reader_writer: LspReaderWriter, server_state: ServerState)
   asserts.is_not_nil(lsp_reader_writer)
   asserts.is_not_nil(server_state)

   self._docs = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
end

function OpenDocumentRegistry:open(file_path: string, uri: Uri, module_info: ModuleInfo):OpenDocument
   asserts.that(self._docs[file_path] == nil)
   local doc = OpenDocument(uri, self._server_state, module_info)
   self._docs[file_path] = doc
   return doc
end

function OpenDocumentRegistry:close(file_path: string)
   asserts.that(self._docs[file_path] ~= nil)
   self._docs[file_path] = nil
end

function OpenDocumentRegistry:try_get(file_path: string):OpenDocument
   return self._docs[file_path]
end

class.setup(OpenDocumentRegistry, "OpenDocumentRegistry", {
   getters =  {
      docs = function(self:OpenDocumentRegistry):{string:OpenDocument}
         return self._docs
      end
   }
})
return OpenDocumentRegistry
