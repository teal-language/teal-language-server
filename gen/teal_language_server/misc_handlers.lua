local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "misc_handlers"


local DiagnosticsPublisher = require("teal_language_server.diagnostics_publisher")
local BuildHandler = require("teal_language_server.build_handler")
local ModuleInfoManager = require("teal_language_server.module_info_manager")
local DiagnosticsHelper = require("teal_language_server.diagnostics_helper")
local args_parser = require("teal_language_server.args_parser")
local TraceStream = require("teal_language_server.trace_stream")
local OpenDocumentRegistry = require("teal_language_server.open_document_registry")
local OpenDocument = require("teal_language_server.open_document")
local ServerState = require("teal_language_server.server_state")
local EnvFactory = require("teal_language_server.env_factory")
local LspReaderWriter = require("teal_language_server.lsp_reader_writer")
local Uri = require("teal_language_server.uri")
local lsp = require("teal_language_server.lsp")
local LspEventsManager = require("teal_language_server.lsp_events_manager")
local uv = require("luv")
local asserts = require("teal_language_server.asserts")
local tracing = require("teal_language_server.tracing")
local class = require("teal_language_server.class")
local tl = require("tl")
local lsp_formatter = require("teal_language_server.lsp_formatter")
local files_util = require("teal_language_server.files_util")
local path_util = require("teal_language_server.path_util")

local indexable_parent_types = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true,
}

local MiscHandlers = {}
















function MiscHandlers:__init(lsp_events_manager, lsp_reader_writer, server_state, env_factory, open_document_registry, trace_stream, args, build_handler, module_info_manager, diagnostics_helper, diagnostics_publisher)
   self._document_manager = open_document_registry
   self._server_state = server_state
   self._env_factory = env_factory
   self._lsp_reader_writer = lsp_reader_writer
   self._lsp_events_manager = lsp_events_manager
   self._build_handler = build_handler
   self._has_handled_initialize = false
   self._trace_stream = trace_stream
   self._cl_args = args
   self._module_info_manager = module_info_manager
   self._diagnostics_helper = diagnostics_helper
   self._diagnostics_publisher = diagnostics_publisher
end

function MiscHandlers:_on_initialize(params, id)
   asserts.that(not self._has_handled_initialize)
   self._has_handled_initialize = true
   local root_path

   if params.rootUri then
      root_path = Uri.to_file_path(Uri.parse(params.rootUri))
   else
      root_path = path_util.canonicalize(params.rootPath)
   end

   asserts.that(files_util.is_directory(root_path), "Expected path to exist at '{}'", root_path)



   if self._cl_args.log_mode == "by_proj_path" then
      local pid = math.floor(uv.os_getpid())
      local new_log_name = root_path:gsub('[\\/:*?"<>|]+', '_') .. "_" .. tostring(pid)
      self._trace_stream:rename_output_file(new_log_name)
   end

   tracing.info(_module_name, "Received initialize request from client. Teal project dir: {}", { root_path })

   self._server_state:initialize(root_path)

   local cwd = path_util.canonicalize(assert(uv.cwd()))
   asserts.that(cwd == self._server_state.teal_project_root_dir)

   self._env_factory:initialize()

   tracing.trace(_module_name, "Sending initialize response message...", {})

   self._lsp_reader_writer:send_rpc(id, {
      capabilities = self._server_state.capabilities,
      serverInfo = {
         name = self._server_state.name,
         version = self._server_state.version,
      },
   })

   self._module_info_manager:initialize()
   self._build_handler:initialize()
   self._diagnostics_publisher:initialize()
end

function MiscHandlers:_on_initialized()
   tracing.debug(_module_name, "Received 'initialized' notification", {})
end

function MiscHandlers:_on_did_open(params)
   local td = params.textDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local content = td.text

   self._module_info_manager:on_opened(file_path, content, uri)

   local module_info = self._module_info_manager:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didOpen' for unknown module at path: {}", { file_path })
   else
      tracing.debug(_module_name, "Received 'didOpen' for module {}", { module_info.module_name })
      self._document_manager:open(file_path, uri, module_info)
   end

   self._diagnostics_publisher:enqueue_build()
end

function MiscHandlers:_on_did_save(params)
   local td = params.textDocument
   local uri = Uri.parse(td.uri)

   local file_path = Uri.to_file_path(uri)
   local module_info = self._module_info_manager:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didSave' for unknown module at path: {}", { file_path })
   else
      tracing.debug(_module_name, "Received 'didSave' for module {}", { module_info.module_name })
   end
end

function MiscHandlers:_on_did_close(params)
   local td = params.textDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didClose' for file at path: {}", { file_path })

   self._module_info_manager:on_closed(file_path)

   self._document_manager:close(file_path)
end

function MiscHandlers:_on_did_change(params)
   local td = params.textDocument
   local uri = Uri.parse(td.uri)
   local changes = params.contentChanges
   local content = changes[1].text

   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didChange' for file at path: {}", { file_path })

   self._module_info_manager:on_changed(file_path, content, uri)
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
   local td = params.textDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local doc = self._document_manager:try_get(file_path)

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      return nil
   end

   tracing.trace(_module_name, "Looking up node info at position: {@}", { pos })
   local node_info = doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end
   tracing.trace(_module_name, "Found node info: {@}", { node_info })
   return node_info, doc
end

function MiscHandlers:_handle_dereference_completion(params, id)
   local pos = params.position
   tracing.debug(_module_name, "Received request for completion at position: {@}", { pos })



   pos.character = pos.character - 1

   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      tracing.trace(_module_name, "No node found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Found node info: {@}", { node_info })

   local env = self._build_handler:get_env()

   local tks



   if node_info.type == "." or node_info.type == ":" then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.debug(_module_name, "Received request for completion at character: {@}", { tks })


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

         tracing.trace(_module_name, "Ignoring completion request in var/simple_type/table_type context", {})
         return
      end
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      tracing.trace(_module_name, "Ignoring completion request for node type: {}", { node_info.type })
      return
   end

   local items = {}
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.debug(_module_name, "Successfully found type_info {@}", { type_info })
      local tr = env.reporter:get_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref, env)
      end


      if type_info.t == tl.typecodes.STRING then
         type_info = tr.types[tr.globals["string"]]
         tracing.trace(_module_name, "Type is string, using global string type info {@}", { type_info })
      end




      local original_str = type_info.str
      tracing.trace(_module_name, "original type_info str: {}", { original_str })

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v, env)
            local was_added
            tracing.trace(_module_name, "Considering field {} with type info {@}", { key, type_info })

            if node_info.type == ":" then
               if type_info.t == tl.typecodes.FUNCTION then

                  if type_info.args and #type_info.args >= 1 then
                     local first_arg_type = doc:resolve_type_ref(type_info.args[1][1], env)
                     if first_arg_type.t == tl.typecodes.SELF or ((first_arg_type.t == tl.typecodes.NOMINAL or first_arg_type.t == tl.typecodes.RECORD or first_arg_type.t == tl.typecodes.STRING) and first_arg_type.str == original_str) then
                        tracing.trace(_module_name, "Adding self method {}", { key })
                        table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
                        was_added = true
                     else
                        tracing.trace(_module_name, "Ignoring method {} with arg type {0x%08x}, type info str {}, first arg str {}", {
                           key, first_arg_type.t, original_str, first_arg_type.str, })
                     end
                  end
               else
                  tracing.trace(_module_name, "Ignoring non-function field {} for self access", { key })
               end
            else
               table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
               was_added = true
            end

            if not was_added then
               tracing.trace(_module_name, "Ignoring field {}", { key })
            end
         end


      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys, env)

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

   tracing.debug(_module_name, "Sending {} completion items back to client", { #items })

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items,
   })
end

function MiscHandlers:_on_completion(params, id)
   local context = params.context

   if context.triggerKind == lsp.completion_trigger_kind.TriggerCharacter then
      self:_handle_dereference_completion(params, id)


   else
      self._lsp_reader_writer:send_rpc(id, nil)
   end
end

function MiscHandlers:_on_signature_help(params, id)
   local pos = params.position


   pos.character = pos.character - 1

   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local output = {}
   tracing.trace(_module_name, "Got nodeinfo: {}", { node_info })

   local tks

   if node_info.type == "(" and node_info.preceded_by then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.trace(_module_name, "Received request for signature help at character: {}", { tks })
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local env = self._build_handler:get_env()
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

   if type_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   output.signatures = {}
   if type_info.t == tl.typecodes.POLY then
      for _, type_ref in ipairs(type_info.types) do
         type_info = doc:resolve_type_ref(type_ref, env)
         local args = doc:get_function_args_string(type_info, env)
         if args ~= nil then
            local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
            table.insert(output.signatures, { label = func_str })

         else
            table.insert(output.signatures, { label = type_info.str })
         end
      end
   else
      local args = doc:get_function_args_string(type_info, env)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, { label = func_str })
      else
         table.insert(output.signatures, { label = type_info.str })
      end
   end

   tracing.debug(_module_name, "[_on_signature_help] Found type info: {}", { type_info })

   self._lsp_reader_writer:send_rpc(id, output)
end

function MiscHandlers:_on_definition(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Received request for on_definition at position: {@}", { pos })

   local tks = {}
   if node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm: {}", { node_info.type })
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local env = self._build_handler:get_env()


   local symbol_name = tks[#tks]
   local symbol_info = doc:find_symbol_declaration(symbol_name, env)

   local type_info
   local file_uri

   if symbol_info then

      tracing.trace(_module_name, "[on_definition] Found symbol declaration for '{}' at {}:{}", { symbol_name, symbol_info.y, symbol_info.x })
      type_info = symbol_info

      if #type_info.file == 0 then
         file_uri = doc.uri
      else
         local full_path
         if path_util.is_absolute(type_info.file) then
            full_path = type_info.file
         else
            full_path = self._server_state.teal_project_root_dir .. "/" .. type_info.file
         end
         file_uri = Uri.uri_from_path(full_path)
      end
   else

      tracing.trace(_module_name, "[on_definition] No symbol declaration found for '{}', falling back to type definition", { symbol_name })
      type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

      if not type_info or type_info.file == nil then
         self._lsp_reader_writer:send_rpc(id, nil)
         return
      end

      tracing.trace(_module_name, "[on_definition] Found type type_info: {}", { type_info })

      if #type_info.file == 0 then
         file_uri = doc.uri
      else
         local full_path
         if path_util.is_absolute(type_info.file) then
            full_path = type_info.file
         else
            full_path = self._server_state.teal_project_root_dir .. "/" .. type_info.file
         end
         file_uri = Uri.uri_from_path(full_path)
      end
   end

   self._lsp_reader_writer:send_rpc(id, {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(type_info.y - 1, type_info.x - 1),
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1),
      },
   })
end

function MiscHandlers:_on_workspace_diagnostic(params, id)
   tracing.debug(_module_name, "Received workspace/diagnostic request", {})

   local workspace_params = params
   local previous_result_id = workspace_params.previousResultId
   local current_result_id = self._server_state:get_workspace_diagnostic_result_id()


   if previous_result_id and previous_result_id == current_result_id then
      tracing.debug(_module_name, "Returning unchanged workspace diagnostics (same result ID: {})", { current_result_id })
      self._lsp_reader_writer:send_rpc(id, {
         items = { {
            kind = lsp.diagnostic_kind.unchanged,
            resultId = current_result_id,
         }, },
      })
      return
   end


   local new_result_id = self._server_state:update_workspace_diagnostic_result_id()

   tracing.debug(_module_name, "Running full workspace build for diagnostics...", {})

   local all_modules = self._build_handler:get_all_modules()
   local build_result = self._build_handler:build(all_modules, nil)

   self._build_handler:sort_files_by_dependency_order(
   all_modules, build_result.global_dep_paths)

   local workspace_items = {}


   for _, module_info in ipairs(all_modules) do
      local uri = module_info.uri
      if not uri then

         uri = Uri.uri_from_path(module_info.path)
      end

      local diagnostics = self._diagnostics_helper:create_diagnostics(module_info)
      table.insert(workspace_items, {
         uri = Uri.tostring(uri),
         kind = lsp.diagnostic_kind.full,
         resultId = new_result_id,
         items = diagnostics,
      })
   end

   tracing.info(_module_name, "Returning workspace diagnostics for {} files with result ID {}", { #workspace_items, new_result_id })

   self._lsp_reader_writer:send_rpc(id, {
      items = workspace_items,
   })
end

function MiscHandlers:_on_hover(params, id)
   local pos = params.position
   tracing.trace(_module_name, "Received request for hover at position: {@}", { pos })
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

   local env = self._build_handler:get_env()
   local td = params.textDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local tks = {}
   if node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm: {}", { node_info.type })

      local tr = doc:_try_get_type_report(env)

      if tr ~= nil then
         local quick_pos_info = tr.by_pos[file_path]

         if quick_pos_info then
            local quick_line_info = quick_pos_info[node_info.parent_start.row + 1]

            if quick_line_info then
               local type_ref = quick_line_info[node_info.parent_start.column + 1]

               if type_ref ~= nil then
                  local type_info = tr.types[type_ref]

                  if type_info and type_info.ref then
                     type_info = tr.types[type_info.ref]
                  end

                  if type_info ~= nil then
                     local type_str = lsp_formatter.show_type(node_info, type_info, doc, env)
                     self._lsp_reader_writer:send_rpc(id, {
                        contents = type_str,
                        range = {
                           start = lsp.position(pos.line, pos.character),
                           ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
                        },
                     })
                     return
                  end
               end
            end
         end
      end

      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.parent_type, ":", node_info.type },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

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

   tracing.trace(_module_name, "Successfully found type_info: {@}", { type_info })

   local type_str = lsp_formatter.show_type(node_info, type_info, doc, env)
   self._lsp_reader_writer:send_rpc(id, {
      contents = type_str,
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
      },
   })
end

function MiscHandlers:_on_type_definition(params, id)
   local pos = params.position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Received request for on_type_definition at position: {@}", { pos })

   local tks = {}
   if node_info.type == "identifier" then

      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't get type definition for anything that isn't an identifier: {}", { node_info.type })
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local env = self._build_handler:get_env()


   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

   if not type_info or type_info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_type_definition] Found type type_info: {}", { type_info })

   local file_uri

   if #type_info.file == 0 then
      file_uri = doc.uri
   else
      local full_path
      if path_util.is_absolute(type_info.file) then
         full_path = type_info.file
      else
         full_path = self._server_state.teal_project_root_dir .. "/" .. type_info.file
      end
      file_uri = Uri.uri_from_path(full_path)
   end

   self._lsp_reader_writer:send_rpc(id, {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(type_info.y - 1, type_info.x - 1),
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1 + #(type_info.str or "")),
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
   self:_add_handler("workspace/diagnostic", self._on_workspace_diagnostic)

   self:_add_handler("textDocument/definition", self._on_definition)
   self:_add_handler("textDocument/typeDefinition", self._on_type_definition)
end

class.setup(MiscHandlers, "MiscHandlers", {})


return MiscHandlers
