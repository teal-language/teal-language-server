
-- Handlers for client requests

local lfs <const> = require("lfs")
local config <const> = require("teal-cli.config")
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

   -- just search in the root as its the client's responsibility to find the root
   local cfg, errs = config.load("tlconfig.lua")
   if not cfg then
      util.log("unable to load config ", errs)
   end
   server.config = cfg

   util.log("responding to initialize...")
   rpc.respond(id, {
      capabilities = server.capabilities,
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
   document.open(td.uri, td.text)
      :type_check_and_publish_result()
end

handlers["textDocument/didClose"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   document.close(td.uri)
end

local function get_doc(params: Params): document.Document
   local td <const> = params.textDocument as lsp.TextDocument
   return document.get(td.uri)
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

handlers["textDocument/hover"] = function(params: Params, id: number)
   local doc <const> = get_doc(params)
   if not doc then
      return
   end
   local pos <const> = params.position as lsp.Position
   local tk <const> = doc:token_at(pos)
   if not tk then
      rpc.respond(id, {
         contents = { " No info found " }
      })
      return
   end
   local info <const> = doc:type_information_at(pos)
   if not info then
      rpc.respond(id, {
         contents = { tk.tk .. ":", " No info found " },
         range = {
            start = lsp.position(tk.y - 1, tk.x - 1),
            ["end"] = lsp.position(tk.y - 1, tk.x + #tk.tk),
         },
      })
      return
   end
   local type_str <const> = doc:show_type(info)
   rpc.respond(id, {
      contents = { tk.tk .. ":", type_str },
      range = {
         start = lsp.position(tk.y - 1, tk.x - 1),
         ["end"] = lsp.position(tk.y - 1, tk.x + #tk.tk),
      },
   })
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
