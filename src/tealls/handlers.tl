
-- Handlers for client requests

local lfs <const> = require("lfs")
local lsp <const> = require("tealls.lsp")
local server <const> = require("tealls.server")
local rpc <const> = require("tealls.rpc")
local document <const> = require("tealls.document")
local uri <const> = require("tealls.uri")
local util <const> = require("tealls.util")

local Name <const> = lsp.Method.Name
local Params <const> = lsp.Method.Params
local Method <const> = lsp.Method.Method

local handlers <const>: {Name:Method} = {}

handlers["initialize"] = function(params: Params, id: number)
   util.assert(not server.initialized, "Server was already initialized")
   server.initialized = true

   if params.rootUri then
      server.root_dir = uri.path_from_uri(params.rootUri as string)
   else
      server.root_dir = params.rootPath as string
   end

   util.log("root_dir: ", server.root_dir)
   util.assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)

   util.log("responding to initialize...")
   rpc.respond(id, {
      capabilities = {
         -- we basically do the bare minimum
         textDocumentSync = {
            openClose = true,
            change = 0,
            save = {
               includeText = true,
            },
         },
      },
      serverInfo = {
         name = server.name,
         version = server.version,
      },
   })
end

handlers["initialized"] = function()
   util.log("Initialized!")
end

handlers["textDocument/didOpen"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   document.open(td.uri, params.text as string)
end

handlers["textDocument/didClose"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   document.close(td.uri)
end

handlers["textDocument/didSave"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = document.get(td.uri)
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   doc:replace_text(params.text as string)
   doc:type_check_and_publish_result()
end


-- Wrap some logs around each handler for debugging
setmetatable(handlers, {
   __index = function(self: {Name:Method}, key: Name): Method
      util.log("   getting handler for ", key)
      local f <const> = rawget(self, key)
      return f and function(p: Params, id: number)
         util.log("   calling handler for ", key, "with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end
})

return handlers
