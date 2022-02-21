
-- Handlers for client requests

local lfs <const> = require("lfs")
local config <const> = require("cyan.config")
local lsp <const> = require("tealls.lsp")
local server <const> = require("tealls.server")
local rpc <const> = require("tealls.rpc")
local document <const> = require("tealls.document")
local uri <const> = require("tealls.uri")
local util <const> = require("tealls.util")
local path_util <const> = require("tealls.path_util")

local Name <const> = lsp.Method.Name
local Params <const> = lsp.Method.Params
local Method <const> = lsp.Method.Method

local handlers <const>: {Name:Method} = {}

handlers["initialize"] = function(params: Params, id: integer)
   util.assert(not server.initialized, "Server was already initialized")
   server.initialized = true

   if params.rootUri then
      server.root_dir = uri.path_from_uri(params.rootUri as string)
   else
      server.root_dir = params.rootPath as string
   end

   util.log("root_dir: ", server.root_dir)
   util.assert(lfs.chdir(server.root_dir), "unable to chdir into " .. server.root_dir)

   local cfg, errs = config.load()
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
   document.open(uri.parse(td.uri), td.text)
      :process_and_publish_results()
end

handlers["textDocument/didClose"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   document.close(uri.parse(td.uri))
end

local function get_doc(params: Params): document.Document
   local td <const> = params.textDocument as lsp.TextDocument
   return document.get(uri.parse(td.uri))
end

handlers["textDocument/didSave"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = document.get(uri.parse(td.uri))
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   doc:update_text(params.text as string)
   doc:process_and_publish_results()
end

handlers["textDocument/definition"] = function(params: Params, id: integer)
   local doc <const> = get_doc(params)
   if not doc then
      return
   end
   local pos <const> = params.position as lsp.Position
   local tk <const> = doc:token_at(pos)
   if not tk then
      rpc.respond(id, nil)
      return
   end
   local info <const> = doc:type_information_at(pos)

   if not info or info.file == nil then
      rpc.respond(id, nil)
      return
   end

   util.log("Found type info: ", info)

   local file_uri:uri.ParsedUri

   if #info.file == 0 then
      file_uri = doc.uri
   else
      if path_util.is_absolute(info.file) then
         file_uri = uri.uri_from_path(info.file)
      else
         file_uri = uri.uri_from_path(path_util.join(server.root_dir, info.file))
      end
   end

   rpc.respond(id, {
      uri = uri.tostring(file_uri),
      range = {
         start = lsp.position(info.y - 1, info.x - 1),
         ["end"] = lsp.position(info.y - 1, info.x - 1),
      },
   })
end

handlers["textDocument/hover"] = function(params: Params, id: integer)
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
         contents = { tk .. ":", " No info found " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #tk),
         },
      })
      return
   end
   local type_str <const> = doc:show_type(info)
   rpc.respond(id, {
      contents = { tk .. ":", type_str },
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #tk),
      },
   })
end

-- Wrap some logs around each handler for debugging
return setmetatable({}, {
   __index = function(_self: {Name:Method}, key: Name): Method
      util.log("   getting handler for ", key)
      local f <const> = rawget(handlers, key)
      return f and function(p: Params, id: integer)
         util.log("   calling handler for '", key, "' with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end
}) as {Name:Method}

-- return handlers
