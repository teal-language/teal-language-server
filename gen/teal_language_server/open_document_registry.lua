local _module_name = "open_document_registry"


local ModuleInfo = require("teal_language_server.module_info")
local asserts = require("teal_language_server.asserts")
local class = require("teal_language_server.class")

local OpenDocumentRegistry = {}







function OpenDocumentRegistry:__init()
   self._docs = {}
end

function OpenDocumentRegistry:open(file_path, module_info)
   asserts.that(self._docs[file_path] == nil)
   self._docs[file_path] = module_info
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
