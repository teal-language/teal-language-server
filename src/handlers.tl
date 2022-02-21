
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
   document.open(uri.parse(td.uri), td.text, td.version)
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
   doc:update_text(params.text as string, td.version)
   doc:process_and_publish_results()
end

handlers["textDocument/didChange"] = function(params: Params)
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = document.get(uri.parse(td.uri))
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   local changes <const> = params.contentChanges as {lsp.TextDocumentContentChangeEvent}
   doc:update_text(changes[1].text as string, td.version)
   doc:process_and_publish_results()
end

handlers["textDocument/completion"] = function(params: Params, id: integer)

   local context = params.context as lsp.CompletionContext

   if context.triggerKind ~= 2 then
      util.log("Ignoring completion request given kind: ", context.triggerKind)
      return
   end

   local doc <const> = get_doc(params)
   if not doc then
      util.log("No doc found for completion request")
      rpc.respond(id, nil)
      return
   end

   local pos <const> = params.position as lsp.Position
   local line = doc:get_line(pos.line + 1)

   if not line then
      util.log("No line found for completion request")
      rpc.respond(id, nil)
      return
   end

   local identifier = line:sub(1, pos.character):match("(%w+)$")

   if not identifier or #identifier == 0 then
      util.log("No identifier found for completion request")
      rpc.respond(id, nil)
      return
   end

   util.log("Looking up type info for identifier: '" .. identifier .. "'")

   local info <const> = doc:get_type_info_for_symbol(identifier, pos)
   local items:{any} = { }

   if info then
      for key, _ in pairs(info.fields) do
         table.insert(items, {label = key})
      end
   end

   rpc.respond(id, {
      isIncomplete = false,
      items = items
   })
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

   util.log("Found type info: ", info)

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
      local f <const> = rawget(handlers, key)
      return f and function(p: Params, id: integer)
         util.log("calling handler for '", key, "'")
         f(p, id)
      end
   end
}) as {Name:Method}

-- return handlers
