
local lfs <const> = require("lfs")
local lsp <const> = require("tealls.lsp")
local server <const> = require("tealls.server")
local rpc <const> = require("tealls.rpc")
local document <const> = require("tealls.document")
local util <const> = require("tealls.util")

local Name <const> = lsp.Method.Name
local Params <const> = lsp.Method.Params
local Method <const> = lsp.Method.Method

local handlers <const>: {Name:Method} = {}

handlers["initialize"] = function(params: Params, id: number)
   if server.initialized then
      error("Server was already initialized")
   end
   server.initialized = true

   if params.rootUri then
      server.root_dir = document.path_from_uri(params.rootUri as string)
   else
      server.root_dir = params.rootPath as string
   end

   util.log("root_dir: ", server.root_dir)
   assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)

   util.log("responding to initialize...")
   rpc.respond(id, {
      capabilities = {
         -- we basically do the bare minimum
         textDocumentSync = {
            openClose = true,
            change = 0,
            save = {
               includeText = 0,
            },
         },
      },
      serverInfo = {
         name = "teal-language-server",
         version = "dev",
      },
   })
end

-- Being able to subtype params here would be real nice
local function type_check(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   document.type_check(td.uri)
end

handlers["textDocument/didOpen"] = type_check
handlers["textDocument/didSave"] = type_check

-- handlers["textDocument/didChange"] = function(params: Params, id: number)
-- end

-- handlers["textDocument/didClose"] = function(params: Params, id: number)
-- end

-- Wrap some logs around each handler for debugging
setmetatable(handlers, {
   __index = function(self: {Name:Method}, key: Name): Method
      util.log("   getting handler for ", key)
      return rawget(self, key) and function(p: Params, id: number)
         local f = rawget(self, key)
         util.log("   calling handler for ", key, "with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end
})

return handlers
