


local lfs = require("lfs")
local config = require("teal-cli.config")
local lsp = require("tealls.lsp")
local server = require("tealls.server")
local rpc = require("tealls.rpc")
local document = require("tealls.document")
local uri = require("tealls.uri")
local util = require("tealls.util")

local Name = lsp.Method.Name
local Params = lsp.Method.Params
local Method = lsp.Method.Method

local handlers = {}

handlers["initialize"] = function(params, id)
   util.assert(not server.initialized, "Server was already initialized")
   server.initialized = true

   if params.rootUri then
      server.root_dir = uri.path_from_uri(params.rootUri)
   else
      server.root_dir = params.rootPath
   end

   util.log("root_dir: ", server.root_dir)
   util.assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)


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

handlers["textDocument/didOpen"] = function(params)
   local td = params.textDocument
   document.open(td.uri, td.text):
   type_check_and_publish_result()
end

handlers["textDocument/didClose"] = function(params)
   local td = params.textDocument
   document.close(td.uri)
end

local function get_doc(params)
   local td = params.textDocument
   return document.get(td.uri)
end

handlers["textDocument/didSave"] = function(params)
   local td = params.textDocument
   local doc = document.get(td.uri)
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   doc:replace_text(params.text)
   doc:type_check_and_publish_result()
end

handlers["textDocument/hover"] = function(params, id)
   local doc = get_doc(params)
   if not doc then
      return
   end
   local pos = params.position
   local tk = doc:token_at(pos)
   if not tk then
      rpc.respond(id, {
         contents = { " No info found " },
      })
      return
   end
   local info = doc:type_information_at(pos)
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
   local type_str = doc:show_type(info)
   rpc.respond(id, {
      contents = { tk.tk .. ":", type_str },
      range = {
         start = lsp.position(tk.y - 1, tk.x - 1),
         ["end"] = lsp.position(tk.y - 1, tk.x + #tk.tk),
      },
   })
end


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