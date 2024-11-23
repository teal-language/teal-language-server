local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "misc_handlers"


local EnvUpdater = require("teal_language_server.env_updater")
local args_parser = require("teal_language_server.args_parser")
local TraceStream = require("teal_language_server.trace_stream")
local DocumentManager = require("teal_language_server.document_manager")
local Document = require("teal_language_server.document")
local ServerState = require("teal_language_server.server_state")
local LspReaderWriter = require("teal_language_server.lsp_reader_writer")
local Path = require("teal_language_server.path")
local Uri = require("teal_language_server.uri")
local lsp = require("teal_language_server.lsp")
local LspEventsManager = require("teal_language_server.lsp_events_manager")
local uv = require("luv")
local asserts = require("teal_language_server.asserts")
local tracing = require("teal_language_server.tracing")
local class = require("teal_language_server.class")
local tl = require("tl")
local lsp_formatter = require("teal_language_server.lsp_formatter")

local indexable_parent_types = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true,
}

local MiscHandlers = {}












function MiscHandlers:__init(lsp_events_manager, lsp_reader_writer, server_state, document_manager, trace_stream, args, env_updater)
   asserts.is_not_nil(env_updater)

   self._document_manager = document_manager
   self._server_state = server_state
   self._lsp_reader_writer = lsp_reader_writer
   self._lsp_events_manager = lsp_events_manager
   self._has_handled_initialize = false
   self._trace_stream = trace_stream
   self._cl_args = args
   self._env_updater = env_updater

end

function MiscHandlers:_on_initialize(params, id)
   asserts.that(not self._has_handled_initialize)
   self._has_handled_initialize = true
   local root_dir_str

   if params.rootUri then
      root_dir_str = Uri.path_from_uri(params.rootUri)
   else
      root_dir_str = params.rootPath
   end

   local root_path = Path(root_dir_str)
   asserts.that(root_path:exists(), "Expected path to exist at '{}'", root_path.value)



   if self._cl_args.log_mode == "by_proj_path" then
      local pid = math.floor(uv.os_getpid())
      local new_log_name = root_path.value:gsub('[\\/:*?"<>|]+', '_') .. "_" .. tostring(pid)
      self._trace_stream:rename_output_file(new_log_name)
   end

   tracing.info(_module_name, "Received initialize request from client. Teal project dir: {}", { root_path.value })

   self._server_state:initialize(root_path)
   self._env_updater:initialize()

   tracing.trace(_module_name, "Sending initialize response message...", {})

   self._lsp_reader_writer:send_rpc(id, {
      capabilities = self._server_state.capabilities,
      serverInfo = {
         name = self._server_state.name,
         version = self._server_state.version,
      },
   })
end

function MiscHandlers:_on_initialized()
   tracing.debug(_module_name, "Received 'initialized' notification", {})
end

function MiscHandlers:_on_did_open(params)
   local td = params.textDocument

   self._document_manager:open(Uri.parse(td.uri), td.text, td.version):
   process_and_publish_results()
end

function MiscHandlers:_on_did_close(params)
   local td = params.textDocument
   self._document_manager:close(Uri.parse(td.uri))
end

function MiscHandlers:_on_did_save(params)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "Unable to find document: {}", { td.uri })
      return
   end

   doc:update_text(params.text, td.version)



   tracing.debug(_module_name, "detected document file saved - enqueuing full env update", {})
   self._env_updater:schedule_env_update()
end

function MiscHandlers:_on_did_change(params)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))
   if not doc then
      tracing.warning(_module_name, "Unable to find document: {}", { td.uri })
      return
   end
   local changes = params.contentChanges
   doc:update_text(changes[1].text, td.version)
   doc:process_and_publish_results()
end

local function split_by_symbols(input, self_type, stop_at)
   local t = {}
   for str in string.gmatch(input, "([^%.%:]+)") do
      if str == "self" then
         table.insert(t, self_type)
      else
         table.insert(t, str)
      end
      if stop_at and stop_at == str then
         break
      end
   end
   return t
end

function MiscHandlers:_get_node_info(params, pos)
   local context = params.context

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      tracing.warning(_module_name, "Ignoring completion request given kind: {}", { context.triggerKind })
      return nil
   end

   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      return nil
   end

   tracing.warning(_module_name, "Received request for completion at position: {}", { pos })
   local node_info = doc:parser_token(pos.line, pos.character)
   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end
   tracing.warning(_module_name, "Found node info at pos", node_info)
   return node_info, doc
end

function MiscHandlers:_on_completion(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.warning(_module_name, "Got nodeinfo: {}", node_info)

   local tks



   if node_info.type == "." or node_info.type == ":" then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.warning(_module_name, "Received request for completion at character: {}", { tks })


   elseif node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end




      tks[#tks] = nil



      if node_info.parent_type == "var" or
         node_info.parent_type == "simple_type" or
         node_info.parent_type == "table_type" then
         self._lsp_reader_writer:send_rpc(id, nil)
         return
      end

   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local items = {}
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.warning(_module_name, "Successfully found type type_info '{}'", type_info)
      local tr = doc:get_type_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref)
      end


      if type_info.t == tl.typecodes.STRING then
         type_info = tr.types[tr.globals["string"]]
      end




      local original_str = type_info.str

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v)

            if node_info.type == ":" then
               if type_info.t == tl.typecodes.FUNCTION then

                  if type_info.args and #type_info.args >= 1 then
                     local first_arg_type = doc:resolve_type_ref(type_info.args[1][1])
                     if first_arg_type.t == tl.typecodes.SELF or (first_arg_type.t == tl.typecodes.NOMINAL and first_arg_type.str == original_str) then
                        tracing.warning(_module_name, "adding " .. key, {})
                        table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
                     else
                        tracing.warning(_module_name, "type info str: " .. original_str .. "first arg str: " .. first_arg_type.str, {})
                     end
                  end
               end
            else
               table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
            end
         end


      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys)

         if type_info.enums then
            for _, enum_value in ipairs(type_info.enums) do
               table.insert(items, { label = enum_value, kind = lsp.typecodes_to_kind[type_info.t] })
            end
         end
      else
         tracing.warning(_module_name, "Unable to get fields for ref type", {})
      end
   end

   if #items == 0 then
      table.insert(items, { label = "(none)" })
   end

   tracing.warning(_module_name, "Sending " .. #items .. " back to client", {})

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items,
   })
end

function MiscHandlers:_on_signature_help(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local output = {}
   tracing.warning(_module_name, "Got nodeinfo: {}", node_info)

   local tks

   if node_info.type == "(" then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.warning(_module_name, "Received request for signature help at character: {}", { tks })
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if type_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   output.signatures = {}
   if type_info.t == tl.typecodes.POLY then
      for _, type_ref in ipairs(type_info.types) do
         type_info = doc:resolve_type_ref(type_ref)
         local args = doc:get_function_args_string(type_info)
         if args ~= nil then
            local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
            table.insert(output.signatures, { label = func_str })

         else
            table.insert(output.signatures, { label = type_info.str })
         end
      end
   else
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, { label = func_str })
      else
         table.insert(output.signatures, { label = type_info.str })
      end
   end

   tracing.warning(_module_name, "[_on_signature_help] Found type info: {}", { type_info })

   self._lsp_reader_writer:send_rpc(id, output)
end

function MiscHandlers:_on_definition(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Received request for hover at position: {}", { pos })

   local tks = {}
   if node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm" .. node_info.type, {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info or type_info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_definition] Found type type_info: {}", { type_info })

   local file_uri

   if #type_info.file == 0 then
      file_uri = doc.uri
   else
      local full_path

      if Path(type_info.file):is_absolute() then
         full_path = type_info.file
      else
         full_path = self._server_state.teal_project_root_dir.value .. "/" .. type_info.file
      end

      local file_path = Path(full_path)
      file_uri = Uri.uri_from_path(file_path.value)
   end

   self._lsp_reader_writer:send_rpc(id, {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(type_info.y - 1, type_info.x - 1),
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1),
      },
   })
end

function MiscHandlers:_on_hover(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, {
         contents = { "Unknown Token:", " Unable to determine what token is under cursor " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character),
         },
      })
      return
   end

   tracing.trace(_module_name, "Received request for hover at position: {}", { pos })

   local tks = {}
   if node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm" .. node_info.type, {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.parent_type, ":", node_info.type },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type info based on token", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.source .. ":", " No type_info found " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   tracing.warning(_module_name, "Successfully found type_info: {}", { type_info })

   local type_str = lsp_formatter.show_type(node_info, type_info, doc)
   self._lsp_reader_writer:send_rpc(id, {
      contents = type_str,
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
      },
   })
end

function MiscHandlers:_add_handler(name, handler)
   self._lsp_events_manager:set_handler(name, function(params, id) handler(self, params, id) end)
end

function MiscHandlers:initialize()
   self:_add_handler("initialize", self._on_initialize)
   self:_add_handler("initialized", self._on_initialized)
   self:_add_handler("textDocument/didOpen", self._on_did_open)
   self:_add_handler("textDocument/didClose", self._on_did_close)
   self:_add_handler("textDocument/didSave", self._on_did_save)
   self:_add_handler("textDocument/didChange", self._on_did_change)
   self:_add_handler("textDocument/completion", self._on_completion)
   self:_add_handler("textDocument/signatureHelp", self._on_signature_help)
   self:_add_handler("textDocument/hover", self._on_hover)


   self:_add_handler("textDocument/definition", self._on_definition)
end

class.setup(MiscHandlers, "MiscHandlers", {})


return MiscHandlers
