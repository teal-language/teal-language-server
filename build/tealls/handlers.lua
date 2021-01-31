local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert
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
   if server.initialized then
      error("Server was already initialized")
   end
   server.initialized = true

   if params.rootUri then
      server.root_dir = document.path_from_uri(params.rootUri)
   else
      server.root_dir = params.rootPath
   end

   util.log("root_dir: ", server.root_dir)
   assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)

   util.log("responding to initialize...")
   rpc.respond(id, {
      capabilities = {

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


local function type_check(params)
   local td = params.textDocument
   document.type_check(td.uri)
end

handlers["textDocument/didOpen"] = type_check
handlers["textDocument/didSave"] = type_check








setmetatable(handlers, {
   __index = function(self, key)
      util.log("   getting handler for ", key)
      return rawget(self, key) and function(p, id)
         local f = rawget(self, key)
         util.log("   calling handler for ", key, "with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end,
})

return handlers
