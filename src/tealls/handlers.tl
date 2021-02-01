
-- Handlers for client requests

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
   util.assert(not server.initialized, "Server was already initialized")
   server.initialized = true

   if params.rootUri then
      server.root_dir = document.path_from_uri(params.rootUri as string)
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
               includeText = false,
            },
         },
      },
      serverInfo = {
         name = server.name,
         version = server.version,
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
