local _module_name = "open_document_registry"

-- <imports>
local ModuleInfo <const> = require("teal_language_server.module_info")
local asserts <const> = require("teal_language_server.asserts")
local class <const> = require("teal_language_server.class")

local record OpenDocumentRegistry
   docs:{string:ModuleInfo}

   _docs:{string:ModuleInfo}

   metamethod __call: function(self: OpenDocumentRegistry): OpenDocumentRegistry
end

function OpenDocumentRegistry:__init()
   self._docs = {}
end

function OpenDocumentRegistry:open(file_path: string, module_info: ModuleInfo)
   asserts.that(self._docs[file_path] == nil)
   self._docs[file_path] = module_info
end

function OpenDocumentRegistry:close(file_path: string)
   asserts.that(self._docs[file_path] ~= nil)
   self._docs[file_path] = nil
end

function OpenDocumentRegistry:try_get(file_path: string):ModuleInfo
   return self._docs[file_path]
end

class.setup(OpenDocumentRegistry, "OpenDocumentRegistry", {
   getters =  {
      docs = function(self:OpenDocumentRegistry):{string:ModuleInfo}
         return self._docs
      end
   }
})
return OpenDocumentRegistry
