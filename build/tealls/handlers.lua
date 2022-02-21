local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table


local lfs = require("lfs")
local config = require("cyan.config")
local lsp = require("tealls.lsp")
local server = require("tealls.server")
local rpc = require("tealls.rpc")
local document = require("tealls.document")
local uri = require("tealls.uri")
local util = require("tealls.util")
local path_util = require("tealls.path_util")

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

handlers["textDocument/didOpen"] = function(params)
   local td = params.textDocument
   document.open(uri.parse(td.uri), td.text, td.version):
   process_and_publish_results()
end

handlers["textDocument/didClose"] = function(params)
   local td = params.textDocument
   document.close(uri.parse(td.uri))
end

local function get_doc(params)
   local td = params.textDocument
   return document.get(uri.parse(td.uri))
end

handlers["textDocument/didSave"] = function(params)
   local td = params.textDocument
   local doc = document.get(uri.parse(td.uri))
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   doc:update_text(params.text, td.version)
   doc:process_and_publish_results()
end

handlers["textDocument/didChange"] = function(params)
   local td = params.textDocument
   local doc = document.get(uri.parse(td.uri))
   if not doc then
      util.log("Unable to find document: ", td.uri)
      return
   end
   local changes = params.contentChanges
   doc:update_text(changes[1].text, td.version)
   doc:process_and_publish_results()
end

handlers["textDocument/completion"] = function(params, id)

   local doc = get_doc(params)
   if not doc then
      rpc.respond(id, nil)
   end

   local pos = params.position
   local line = doc:get_line(pos.line + 1)
   local identifier = line:sub(1, pos.character - 1):match("(%w+)$")

   util.log("Looking up type info for identifier: '" .. identifier .. "'")

   local info = doc:get_type_info_for_symbol(identifier, pos)
   local items = {}

   if info then
      for key, _ in pairs(info.fields) do
         table.insert(items, { label = key })
      end
   end

   rpc.respond(id, {
      isIncomplete = false,
      items = items,
   })
end

handlers["textDocument/definition"] = function(params, id)
   local doc = get_doc(params)
   if not doc then
      return
   end
   local pos = params.position
   local tk = doc:token_at(pos)
   if not tk then
      rpc.respond(id, nil)
      return
   end
   local info = doc:type_information_at(pos)

   if not info or info.file == nil then
      rpc.respond(id, nil)
      return
   end

   util.log("Found type info: ", info)

   local file_uri

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
         contents = { tk .. ":", " No info found " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #tk),
         },
      })
      return
   end

   util.log("Found type info: ", info)

   local type_str = doc:show_type(info)
   rpc.respond(id, {
      contents = { tk .. ":", type_str },
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #tk),
      },
   })
end


return setmetatable({}, {
   __index = function(_self, key)
      util.log("   getting handler for ", key)
      local f = rawget(handlers, key)
      return f and function(p, id)
         util.log("   calling handler for '", key, "' with")
         util.log("          id: ", id)
         util.log("      params: ", p)
         f(p, id)
         util.log("   done handler for ", key)
      end
   end,
})