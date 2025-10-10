local _module_name = "misc_handlers"

-- <imports>
local EnvManager <const> = require("teal_language_server.env_manager")
local ModuleInfoManager <const> = require("teal_language_server.module_info_manager")
local DiagnosticsHelper <const> = require("teal_language_server.diagnostics_helper")
local args_parser <const> = require("teal_language_server.args_parser")
local TraceStream <const> = require("teal_language_server.trace_stream")
local OpenDocumentRegistry <const> = require("teal_language_server.open_document_registry")
local OpenDocument <const> = require("teal_language_server.open_document")
local ServerState <const> = require("teal_language_server.server_state")
local EnvFactory <const> = require("teal_language_server.env_factory")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local Uri <const> = require("teal_language_server.uri")
local lsp <const> = require("teal_language_server.lsp")
local LspEventsManager <const> = require("teal_language_server.lsp_events_manager")
local uv <const> = require("luv")
local asserts <const> = require("teal_language_server.asserts")
local tracing <const> = require("teal_language_server.tracing")
local class <const> = require("teal_language_server.class")
local tl <const> = require("tl")
local lsp_formatter <const> = require("teal_language_server.lsp_formatter")
local files_util <const> = require("teal_language_server.files_util")
local path_util <const> = require("teal_language_server.path_util")

local indexable_parent_types <const>: {string:boolean} = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true
}

local record MiscHandlers
   _trace_stream: TraceStream
   _document_manager: OpenDocumentRegistry
   _server_state: ServerState
   _env_factory: EnvFactory
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager
   _env_manager: EnvManager
   _module_content_registry: ModuleInfoManager
   _diagnostics_publisher: DiagnosticsHelper
   _has_handled_initialize: boolean
   _cl_args: args_parser.CommandLineArgs

   metamethod __call: function(self: MiscHandlers, lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, env_factory: EnvFactory, open_document_registry: OpenDocumentRegistry, trace_stream: TraceStream, args:args_parser.CommandLineArgs, env_manager: EnvManager, module_info_manager: ModuleInfoManager, diagnostics_helper: DiagnosticsHelper): MiscHandlers
end

function MiscHandlers:__init(lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, env_factory: EnvFactory, open_document_registry: OpenDocumentRegistry, trace_stream: TraceStream, args:args_parser.CommandLineArgs, env_manager: EnvManager, module_info_manager: ModuleInfoManager, diagnostics_helper: DiagnosticsHelper)
   self._document_manager = open_document_registry
   self._server_state = server_state
   self._env_factory = env_factory
   self._lsp_reader_writer = lsp_reader_writer
   self._lsp_events_manager = lsp_events_manager
   self._env_manager = env_manager
   self._has_handled_initialize = false
   self._trace_stream = trace_stream
   self._cl_args = args
   self._module_content_registry = module_info_manager
   self._diagnostics_publisher = diagnostics_helper
end

function MiscHandlers:_on_initialize(params:lsp.Method.Params, id:integer):nil
   asserts.that(not self._has_handled_initialize)
   self._has_handled_initialize= true
   local root_path:string

   if params.rootUri then
      root_path = Uri.to_file_path(Uri.parse(params.rootUri as string))
   else
      root_path = path_util.canonicalize(params.rootPath as string)
   end

   asserts.that(files_util.is_directory(root_path), "Expected path to exist at '{}'", root_path)

   -- Now that we have the project path, rename log file so it is more discoverable
   -- so we can do project specific debugging more easily
   if self._cl_args.log_mode == "by_proj_path" then
      local pid = math.floor(uv.os_getpid())
      local new_log_name = root_path:gsub('[\\/:*?"<>|]+', '_') .. "_" .. tostring(pid)
      self._trace_stream:rename_output_file(new_log_name)
   end

   tracing.info(_module_name, "Received initialize request from client. Teal project dir: {}", {root_path})

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

   self._module_content_registry:initialize()
   self._env_manager:initialize()
end

function MiscHandlers:_on_initialized():nil
   tracing.debug(_module_name, "Received 'initialized' notification", {})
end

function MiscHandlers:_on_did_open(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local content = td.text

   self._module_content_registry:on_opened(file_path, content, uri)

   local module_info = self._module_content_registry:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didOpen' for unknown module at path: {}", {file_path})
   else
      tracing.debug(_module_name, "Received 'didOpen' for module {}", {module_info.module_name})
      self._document_manager:open(file_path, uri, module_info)
   end
end

function MiscHandlers:_on_did_save(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)

   local file_path = Uri.to_file_path(uri)
   local module_info = self._module_content_registry:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didSave' for unknown module at path: {}", {file_path})
   else
      tracing.debug(_module_name, "Received 'didSave' for module {}", {module_info.module_name})
   end
end

function MiscHandlers:_on_did_close(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didClose' for file at path: {}", {file_path})

   self._module_content_registry:on_closed(file_path)

   self._document_manager:close(file_path)
end

function MiscHandlers:_on_did_change(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local changes <const> = params.contentChanges as {lsp.TextDocumentContentChangeEvent}
   local content = changes[1].text as string

   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didChange' for file at path: {}", {file_path})

   self._module_content_registry:on_changed(file_path, content, uri)
end

local function split_by_symbols(input: string, self_type: string, stop_at?: string): {string}
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

function MiscHandlers:_get_node_info(params:lsp.Method.Params, pos: lsp.Position): OpenDocument.NodeInfo, OpenDocument
   local context = params.context as lsp.CompletionContext

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      tracing.warning(_module_name, "Ignoring completion request given kind: {}", {context.triggerKind})
      return nil
   end

   local td <const> = params.textDocument as lsp.TextDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local doc <const> = self._document_manager:try_get(file_path)

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      return nil
   end

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end
   tracing.trace(_module_name, "Found node info: {@}", {node_info})
   return node_info, doc
end

function MiscHandlers:_on_completion(params:lsp.Method.Params, id:integer):nil
   local pos = params.position as lsp.Position
   tracing.debug(_module_name, "Received request for completion at position: {@}", {pos})

   -- Subtract one since neovim passes the character where the cursor is, which is after the '.' / ':'
   -- and this position doesn't exist in the doc so can lead to tree sitter query fails
   pos.character = pos.character - 1

   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      tracing.trace(_module_name, "No node found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Found node info: {@}", {node_info})

   local env = self._env_manager:get_env()

   local tks: {string}

   -- literally at the . or : and are trying to autocomplete
   -- preceded_by should have everything we need in it.
   if node_info.type == "." or node_info.type == ":" then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.debug(_module_name, "Received request for completion at character: {@}", {tks})

   -- completion request in the middle of a word like in "node_info.par" while typing "parent_source"
   elseif node_info.type == "identifier" then
      -- the types that we would need to index into to get type info from
      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end

      -- takes it back to the just after the first dot, then does completion
      -- if there's only one symbol, will return an empty list and type_information_for_tokens will just
      -- show what's in scope
      tks[#tks] = nil

      -- trying to define something new, probably don't want the in-scope thing to popup
      -- we could probably help complete simple types
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

   local items:{any} = { }
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.debug(_module_name, "Successfully found type_info {@}", {type_info})
      local tr = env.reporter:get_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref, env)
      end

      -- string
      if type_info.t == tl.typecodes.STRING then
         type_info = tr.types[tr.globals["string"]]
      end

      -- this seemed to be the best way to compare the first arg with itself when comparing ":",
      -- sometimes the types come in as nominal and don't resolve all the way back, so the name is
      -- what seems to work the most reliably
      local original_str = type_info.str

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v, env)
            local was_added:boolean
            -- self based access should only show functions
            if node_info.type == ":" then
               if type_info.t == tl.typecodes.FUNCTION then
                  -- local args = doc:get_function_args_string(type_info)
                  if type_info.args and #type_info.args >= 1 then
                     local first_arg_type = doc:resolve_type_ref(type_info.args[1][1], env)
                     if first_arg_type.t == tl.typecodes.SELF or ((first_arg_type.t == tl.typecodes.NOMINAL or first_arg_type.t == tl.typecodes.RECORD) and first_arg_type.str == original_str) then
                        tracing.trace(_module_name, "Adding self method {}", {key})
                        table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
                        was_added = true
                     else
                        tracing.trace(_module_name, "Ignoring method {} with arg type {0x%08x}, type info str {}, first arg str {}", {
                           key, first_arg_type.t, original_str, first_arg_type.str})
                     end
                  end
               end
            else
               table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
               was_added = true
            end

            if not was_added then
               tracing.trace(_module_name, "Ignoring field {}", {key})
            end
         end

      -- at a table, we might be able to help resolve the keys!
      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys, env)

         if type_info.enums then
            for _, enum_value in ipairs(type_info.enums) do
               table.insert(items, {label = enum_value, kind = lsp.typecodes_to_kind[type_info.t]})
            end
         end
      else
         tracing.warning(_module_name, "Unable to get fields for ref type", {})
      end
   end

   if #items == 0 then
      table.insert(items, {label = "(none)"})
   end

   tracing.debug(_module_name, "Sending {} completion items back to client", {#items})

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items
   })
end

function MiscHandlers:_on_signature_help(params:lsp.Method.Params, id:integer):nil
   local pos = params.position as lsp.Position

   -- Subtract one to get function identifier instead of bracket
   pos.character = pos.character - 1

   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local output: lsp_formatter.SignatureHelp = {}
   tracing.trace(_module_name, "Got nodeinfo: {}", {node_info})

   local tks: {string}

   if node_info.type == "(" then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.trace(_module_name, "Received request for signature help at character: {}", {tks})
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local env = self._env_manager:get_env()
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
            table.insert(output.signatures, {label = func_str})

         else
            table.insert(output.signatures, {label = type_info.str})
         end
      end
   else
      local args = doc:get_function_args_string(type_info, env)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, {label = func_str})
      else
         table.insert(output.signatures, {label = type_info.str})
      end
   end

   tracing.debug(_module_name, "[_on_signature_help] Found type info: {}", {type_info})

   self._lsp_reader_writer:send_rpc(id, output)
end

function MiscHandlers:_on_definition(params:lsp.Method.Params, id:integer):nil
   local pos <const> = params.position as lsp.Position
   local node_info, doc = self:_get_node_info(params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "Received request for on_definition at position: {@}", {pos})

   local tks: {string} = {}
   if node_info.type == "identifier" then
      -- parent types that show up with multiparts
      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm: {}", {node_info.type})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local env = self._env_manager:get_env()
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character, env)

   if not type_info or type_info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_definition] Found type type_info: {}", {type_info})

   local file_uri: Uri

   if #type_info.file == 0 then
      file_uri = doc.uri
   else
      local full_path: string

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
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1),
      },
   })
end


function MiscHandlers:_on_workspace_diagnostic(params:lsp.Method.Params, id:integer):nil
   tracing.debug(_module_name, "Received workspace/diagnostic request", {})

   local workspace_params = params as lsp.WorkspaceDiagnosticParams
   local previous_result_id = workspace_params.previousResultId
   local current_result_id = self._server_state:get_workspace_diagnostic_result_id()

   -- Check if we can return unchanged result for incremental updates
   if previous_result_id and previous_result_id == current_result_id then
      tracing.debug(_module_name, "Returning unchanged workspace diagnostics (same result ID: {})", {current_result_id})
      self._lsp_reader_writer:send_rpc(id, {
         items = {{
            kind = lsp.diagnostic_kind.unchanged,
            resultId = current_result_id,
         }}
      } as lsp.WorkspaceDiagnosticReport)
      return
   end

   -- Generate new result ID for this diagnostic run
   local new_result_id = self._server_state:update_workspace_diagnostic_result_id()

   tracing.debug(_module_name, "Running full workspace build for diagnostics...", {})
   local all_modules = self._env_manager:do_full_build()

   local workspace_items: {lsp.WorkspaceDiagnosticReportItem} = {}

   for _, module_info in ipairs(all_modules) do
      local uri = module_info.uri
      if not uri then
         -- Create URI for unopened files
         uri = Uri.uri_from_path(module_info.path)
      end

      local diagnostics = self._diagnostics_publisher:create_diagnostics(module_info)
      table.insert(workspace_items, {
         uri = Uri.tostring(uri),
         kind = lsp.diagnostic_kind.full,
         resultId = new_result_id,
         items = diagnostics,
      })
   end

   tracing.info(_module_name, "Returning workspace diagnostics for {} files with result ID {}", {#workspace_items, new_result_id})

   self._lsp_reader_writer:send_rpc(id, {
      items = workspace_items
   } as lsp.WorkspaceDiagnosticReport)
end

function MiscHandlers:_on_hover(params:lsp.Method.Params, id:integer):nil
   local pos <const> = params.position as lsp.Position
   tracing.trace(_module_name, "Received request for hover at position: {@}", {pos})
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

   local tks: {string} = {}
   if node_info.type == "identifier" then
      -- parent types that show up with multiparts
      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm: {}", {node_info.type})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.parent_type, ":", node_info.type },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   local env = self._env_manager:get_env()
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

   tracing.trace(_module_name, "Successfully found type_info: {@}", {type_info})

   local type_str <const> = lsp_formatter.show_type(node_info, type_info, doc, env)
   self._lsp_reader_writer:send_rpc(id, {
      contents = type_str,
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
      },
   })
end

function MiscHandlers:_add_handler(name:lsp.Method.Name, handler:function(MiscHandlers, lsp.Method.Params, integer):nil)
   self._lsp_events_manager:set_handler(name, function(params:lsp.Method.Params, id:integer) handler(self, params, id) end)
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

   -- TODO - figure out what defintion/declaration vs type definition/declaration should go to
   self:_add_handler("textDocument/definition", self._on_definition)
end

class.setup(MiscHandlers, "MiscHandlers", {
})

return MiscHandlers
