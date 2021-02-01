


local lfs = require("lfs")
local lsp = require("tealls.lsp")
local server = require("tealls.server")
local rpc = require("tealls.rpc")
local document = require("tealls.document")
local util = require("tealls.util")

local Name = lsp.Method.Name
local Params = lsp.Method.Params
local Method = lsp.Method.Method

local handlers = {}

handlers["initialize"] = function(params, id)
   util.assert(not server.initialized, "Server was already initialized")
   server.initialized = true

   if params.rootUri then
      server.root_dir = document.path_from_uri(params.rootUri)
   else
      server.root_dir = params.rootPath
   end

   util.log("root_dir: ", server.root_dir)
   util.assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)

   util.log("responding to initialize...")
   rpc.respond(id, {
      capabilities = {

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


local function type_check(params)
   local td = params.textDocument
   document.type_check(td.uri)
end

handlers["textDocument/didOpen"] = type_check
handlers["textDocument/didSave"] = type_check








setmetatable(handlers, {
   __index = function(self, key)
      util.log("   getting handler for ", key)
      local f = rawget(self, key)
      return f and function(p, id)
         util.log("   calling handler for ", key, "with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end,
})

return handlers
