local _module_name = "misc_handlers"

-- <imports>
local teal_helper <const> = require("teal_language_server.teal_helper")
local tree_sitter_helper <const> = require("teal_language_server.tree_sitter_helper")
local ModuleInfo <const> = require("teal_language_server.module_info")
local DiagnosticsPublisher <const> = require("teal_language_server.diagnostics_publisher")
local BuildHandler <const> = require("teal_language_server.build_handler")
local ModuleInfoManager <const> = require("teal_language_server.module_info_manager")
local DiagnosticsHelper <const> = require("teal_language_server.diagnostics_helper")
local args_parser <const> = require("teal_language_server.args_parser")
local TraceStream <const> = require("teal_language_server.trace_stream")
local OpenDocumentRegistry <const> = require("teal_language_server.open_document_registry")
local ServerState <const> = require("teal_language_server.server_state")
local EnvFactory <const> = require("teal_language_server.env_factory")
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
local debug_flags <const> = require("teal_language_server.debug_flags")

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
   _lsp_events_manager: LspEventsManager
   _build_handler: BuildHandler
   _module_info_manager: ModuleInfoManager
   _diagnostics_helper: DiagnosticsHelper
   _diagnostics_publisher: DiagnosticsPublisher
   _has_handled_initialize: boolean
   _cl_args: args_parser.CommandLineArgs

   metamethod __call: function(self: MiscHandlers, lsp_events_manager:LspEventsManager, server_state: ServerState, env_factory: EnvFactory, open_document_registry: OpenDocumentRegistry, trace_stream: TraceStream, args:args_parser.CommandLineArgs, build_handler: BuildHandler, module_info_manager: ModuleInfoManager, diagnostics_helper: DiagnosticsHelper, diagnostics_publisher: DiagnosticsPublisher): MiscHandlers
end

function MiscHandlers:__init(lsp_events_manager:LspEventsManager, server_state: ServerState, env_factory: EnvFactory, open_document_registry: OpenDocumentRegistry, trace_stream: TraceStream, args:args_parser.CommandLineArgs, build_handler: BuildHandler, module_info_manager: ModuleInfoManager, diagnostics_helper: DiagnosticsHelper, diagnostics_publisher: DiagnosticsPublisher)
   self._document_manager = open_document_registry
   self._server_state = server_state
   self._env_factory = env_factory
   self._lsp_events_manager = lsp_events_manager
   self._build_handler = build_handler
   self._has_handled_initialize = false
   self._trace_stream = trace_stream
   self._cl_args = args
   self._module_info_manager = module_info_manager
   self._diagnostics_helper = diagnostics_helper
   self._diagnostics_publisher = diagnostics_publisher
end

function MiscHandlers:_on_initialize(params:lsp.Method.Params):any
   asserts.that(not self._has_handled_initialize)
   self._has_handled_initialize= true

   tracing.trace(_module_name, "Received _on_initialize request with data {@}", {params})

   local root_path:string

   -- Sometimes it can be json.null so check type explicitly
   if type(params.rootUri) == "string" then
      tracing.trace(_module_name, "Received rootUri {}", {params.rootUri})
      root_path = Uri.to_file_path(Uri.parse(params.rootUri as string))
   else
      assert(type(params.rootPath) == "string",
         "Did not receive valid root path or root URI from client")
      tracing.trace(_module_name, "Received params.rootPath {}", {params.rootPath})
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

   self._module_info_manager:initialize()
   self._build_handler:initialize()
   self._diagnostics_publisher:initialize()

   return {
      capabilities = self._server_state.capabilities,
      serverInfo = {
         name = self._server_state.name,
         version = self._server_state.version,
      },
   }
end

function MiscHandlers:_on_initialized():any
   tracing.debug(_module_name, "Received 'initialized' notification", {})
   return nil
end

function MiscHandlers:_on_did_open(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   local content = td.text

   self._module_info_manager:on_opened(file_path, content, uri)

   local module_info = self._module_info_manager:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didOpen' for unknown module at path: {}", {file_path})
   else
      tracing.debug(_module_name, "Received 'didOpen' for module {}", {module_info.module_name})
      self._document_manager:open(file_path, module_info)
   end

   self._diagnostics_publisher:enqueue_build()
end

function MiscHandlers:_on_did_save(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)

   local file_path = Uri.to_file_path(uri)
   local module_info = self._module_info_manager:try_get_module_info(file_path)

   if module_info == nil then
      tracing.warning(_module_name, "Received 'didSave' for unknown module at path: {}", {file_path})
   else
      tracing.debug(_module_name, "Received 'didSave' for module {}", {module_info.module_name})
   end

   -- Might as well take this opportunity to see if any unopened files need to be invalidated
   local all_modules = self._build_handler:get_all_modules()
   local build_changed = self._build_handler:check_unopened_files_for_invalidation(all_modules)

   if build_changed then
      self._diagnostics_publisher:enqueue_build()
   end
end

function MiscHandlers:_on_did_close(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument

   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didClose' for file at path: {}", {file_path})

   self._module_info_manager:on_closed(file_path)

   self._document_manager:close(file_path)
end

function MiscHandlers:_on_did_change(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local changes <const> = params.contentChanges as {lsp.TextDocumentContentChangeEvent}
   local content = changes[1].text as string

   local file_path = Uri.to_file_path(uri)

   tracing.debug(_module_name, "Received 'didChange' for file at path: {}", {file_path})

   self._module_info_manager:on_changed(file_path, content, uri)
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

function MiscHandlers:_add_completions_for_type(type_info: tl.TypeInfo, env: tl.Env, instance_functions_only: boolean, items: {any})
   for key, v in pairs(type_info.fields) do
      local field_type_info = teal_helper.resolve_type_ref(v, env)

      local was_added:boolean

      tracing.trace(_module_name, "Considering field {} with type info {@}", {key, field_type_info})

      -- self based access should only show functions
      if instance_functions_only then
         if field_type_info.t == tl.typecodes.FUNCTION then
            -- local args = doc:get_function_args_string(field_type_info)
            if field_type_info.args and #field_type_info.args >= 1 then
               local first_arg_type = teal_helper.resolve_type_ref(field_type_info.args[1][1], env)

               if first_arg_type.t == tl.typecodes.SELF or ((first_arg_type.t == tl.typecodes.NOMINAL
                     or first_arg_type.t == tl.typecodes.RECORD or first_arg_type.t == tl.typecodes.STRING)
                     and first_arg_type.str == field_type_info.str) then

                  tracing.trace(_module_name, "Adding self method {}", {key})
                  table.insert(items, {label = key, kind = lsp.typecodes_to_kind[field_type_info.t]})
                  was_added = true
               else
                  tracing.trace(_module_name, "Ignoring method {} with arg type {@}, type info str {}, first arg str {}", {
                     key, first_arg_type.t, field_type_info.str, first_arg_type.str})
               end
            end
         else
            tracing.trace(_module_name, "Ignoring non-instance-function field {} for self access", {key})
         end
      else
         table.insert(items, {label = key, kind = lsp.typecodes_to_kind[field_type_info.t]})
         was_added = true
      end

      if not was_added then
         tracing.trace(_module_name, "Ignoring field {}", {key})
      end
   end
end

function MiscHandlers:_handle_forced_completion(doc: ModuleInfo, pos: lsp.Position, file_path: string):any
   tracing.debug(_module_name, "Received request for force completion at position: {@}", {pos})

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = tree_sitter_helper.get_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.trace(_module_name, "No node found at given position", {})
      return nil
   end

   local env = self._build_handler:get_env()
   local tr <const> = env.reporter and env.reporter:get_report()

   if tr == nil then
      tracing.trace(_module_name, "No type report available", {})
      return nil
   end

   local quick_pos_info = tr.by_pos[file_path]

   if not quick_pos_info then
      tracing.trace(_module_name, "No quick position info available for file: {}", {file_path})
      return nil
   end

   local quick_line_info = quick_pos_info[node_info.start.row + 1]

   if not quick_line_info then
      tracing.trace(_module_name, "No quick line info available for line: {}", {node_info.start.row + 1})
      return nil
   end

   local type_ref = quick_line_info[node_info.start.column + 1]

   if type_ref == nil then
      tracing.trace(_module_name, "No type reference available for column: {}", {node_info.start.column + 1})
      return nil
   end

   local type_info = tr.types[type_ref]

   if type_info and type_info.ref then
      type_info = tr.types[type_info.ref]
   end

   if not type_info or not type_info.fields then
      tracing.trace(_module_name, "No type info found for type reference: {}", {type_ref})
      return nil
   end

   local items:{any} = { }

   for key, v in pairs(type_info.fields) do
      local field_type_info = teal_helper.resolve_type_ref(v, env)
      table.insert(items, {label = key, kind = lsp.typecodes_to_kind[field_type_info.t]})
   end

   tracing.trace(_module_name, "Found {} completion items: {@}", {#items, items})
   return {
      isIncomplete = false,
      items = items
   }
end

function MiscHandlers:_try_handle_dereference_completion(doc: ModuleInfo, pos: lsp.Position):any
   tracing.debug(_module_name, "Received request for completion at position: {@}", {pos})

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = tree_sitter_helper.guess_leaf_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.trace(_module_name, "No node found at given position", {})
      return nil
   end

   tracing.trace(_module_name, "Found node info: {@}", {node_info})

   local env = self._build_handler:get_env()

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

         tracing.trace(_module_name, "Ignoring completion request in var/simple_type/table_type context", {})
         return nil
      end
   else
      tracing.trace(_module_name, "Ignoring completion request for node type: {}", {node_info.type})
      return nil
   end

   local items:{any} = { }
   local type_info = teal_helper.type_information_for_tokens(doc, tks, pos.line, pos.character, env)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.debug(_module_name, "Successfully found type_info {@}", {type_info})
      local tr = env.reporter:get_report()

      if type_info.ref then
         type_info = teal_helper.resolve_type_ref(type_info.ref, env)
      end

      -- string
      if type_info.t == tl.typecodes.STRING then
         type_info = tr.types[tr.globals["string"]]
         tracing.trace(_module_name, "Type is string, using global string type info {@}", {type_info})
      end

      -- this seemed to be the best way to compare the first arg with itself when comparing ":",
      -- sometimes the types come in as nominal and don't resolve all the way back, so the name is
      -- what seems to work the most reliably
      tracing.trace(_module_name, "Processing type_info str: {}", {type_info.str})

      if type_info.fields then
         local instance_functions_only = node_info.type == ":"
         self:_add_completions_for_type(type_info, env, instance_functions_only, items)

      -- at a table, we might be able to help resolve the keys!
      elseif type_info.keys then
         type_info = teal_helper.resolve_type_ref(type_info.keys, env)

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

   return {
      isIncomplete = false,
      items = items
   }
end

function MiscHandlers:_on_completion(params:lsp.Method.Params):any
   local context = params.context as lsp.CompletionContext
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)
   local module_info <const> = self._document_manager:try_get(file_path)

   local result: any

   local pos = params.position as lsp.Position
   -- Subtract one since neovim passes the character where the cursor is, which is after the '.' / ':'
   -- and this position doesn't exist in the module_info so can lead to tree sitter query fails
   pos.character = pos.character - 1

   if context.triggerKind == lsp.completion_trigger_kind.TriggerCharacter then
      result = self:_try_handle_dereference_completion(module_info, pos)
   elseif context.triggerKind == lsp.completion_trigger_kind.Invoked then
      result = self:_handle_forced_completion(module_info, pos, file_path)
   else
      result = nil
      tracing.warning(_module_name, "Unknown completion trigger kind: {}", {context.triggerKind})
   end

   return result
end

function MiscHandlers:_on_signature_help(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)
   local doc <const> = self._document_manager:try_get(file_path)

   local pos = params.position as lsp.Position
   -- Subtract one to get function identifier instead of bracket
   pos.character = pos.character - 1

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = tree_sitter_helper.guess_leaf_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end

   local output: lsp_formatter.SignatureHelp = {}
   tracing.trace(_module_name, "Got nodeinfo: {}", {node_info})

   local tks: {string}

   if node_info.type == "(" and node_info.preceded_by then
      tks = split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.trace(_module_name, "Received request for signature help at character: {}", {tks})
   else
      return nil
   end

   local env = self._build_handler:get_env()
   local type_info = teal_helper.type_information_for_tokens(doc, tks, pos.line, pos.character, env)

   if type_info == nil then
      return nil
   end

   output.signatures = {}
   if type_info.t == tl.typecodes.POLY then
      for _, type_ref in ipairs(type_info.types) do
         type_info = teal_helper.resolve_type_ref(type_ref, env)
         local args = teal_helper.get_function_args_string(doc, type_info)
         if args ~= nil then
            local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
            table.insert(output.signatures, {label = func_str})

         else
            table.insert(output.signatures, {label = type_info.str})
         end
      end
   else
      local args = teal_helper.get_function_args_string(doc, type_info)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, {label = func_str})
      else
         table.insert(output.signatures, {label = type_info.str})
      end
   end

   tracing.debug(_module_name, "[_on_signature_help] Found type info: {}", {type_info})

   return output
end

function MiscHandlers:_on_definition(params:lsp.Method.Params):any
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)
   local doc <const> = self._document_manager:try_get(file_path)

   local pos = params.position as lsp.Position

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = tree_sitter_helper.guess_leaf_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
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
      return nil
   end

   local env = self._build_handler:get_env()

   -- First, try to find the symbol declaration (where the variable is declared)
   local symbol_name = tks[#tks]  -- Get the last token which should be the identifier

   -- TODO - resolve ambiguous cases by closest position?
   local symbol_info = teal_helper.find_symbol_declaration(doc, symbol_name, env)

   local type_info: tl.TypeInfo
   local file_uri: Uri

   if symbol_info then
      -- Found the symbol declaration, use that
      tracing.trace(_module_name, "[on_definition] Found symbol declaration for '{}' at {}:{}", {symbol_name, symbol_info.y, symbol_info.x})
      type_info = symbol_info

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
   else
      -- Fall back to type information if no symbol declaration found
      tracing.trace(_module_name, "[on_definition] No symbol declaration found for '{}', falling back to type definition", {symbol_name})
      type_info = teal_helper.type_information_for_tokens(doc, tks, pos.line, pos.character, env)

      if not type_info or type_info.file == nil then
         return nil
      end

      tracing.trace(_module_name, "[on_definition] Found type type_info: {}", {type_info})

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
   end

   return {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(type_info.y - 1, type_info.x - 1),
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1),
      },
   }
end

function MiscHandlers:_on_workspace_diagnostic(params:lsp.Method.Params):any
   tracing.debug(_module_name, "Received workspace/diagnostic request", {})

   local workspace_params = params as lsp.WorkspaceDiagnosticParams
   local previous_result_id = workspace_params.previousResultId
   local current_result_id = self._server_state:get_workspace_diagnostic_result_id()

   -- Check if we can return unchanged result for incremental updates
   if previous_result_id and previous_result_id == current_result_id then
      tracing.debug(_module_name, "Returning unchanged workspace diagnostics (same result ID: {})", {current_result_id})

      local result:lsp.WorkspaceDiagnosticReport = {
         items = {{
            kind = lsp.diagnostic_kind.unchanged,
            resultId = current_result_id,
         }}
      }

      return result
   end

   -- Generate new result ID for this diagnostic run
   local new_result_id = self._server_state:update_workspace_diagnostic_result_id()

   tracing.debug(_module_name, "Running full workspace build for diagnostics...", {})

   self._build_handler:remove_deleted_modules()
   local all_modules = self._build_handler:get_all_modules()
   local build_result = self._build_handler:build(all_modules, nil)

   self._build_handler:sort_files_by_dependency_order(
      all_modules, build_result.global_dep_paths)

   local workspace_items: {lsp.WorkspaceDiagnosticReportItem} = {}

   -- Use sorted modules so that diagnostics related to dependencies appear first
   for _, module_info in ipairs(all_modules) do
      local uri = module_info.uri
      if not uri then
         -- Create URI for unopened files
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

   tracing.info(_module_name, "Returning workspace diagnostics for {} files with result ID {}", {#workspace_items, new_result_id})

   return {
      items = workspace_items
   } as lsp.WorkspaceDiagnosticReport
end

function MiscHandlers:_on_set_trace_modules(params:lsp.Method.Params):any
   tracing.debug(_module_name, "Received teal/setTraceModules request", {})

   local trace_params = params as lsp.SetTraceModulesParams
   local modules = trace_params.modules

   -- Only update if modules were provided (not nil)
   if modules ~= nil then
      tracing.set_trace_modules(modules)
      tracing.info(_module_name, "Updated trace modules to: {@}", {modules})
   else
      tracing.debug(_module_name, "Query-only request, not modifying trace modules")
   end

   -- Return the currently enabled modules
   local current_modules = tracing.get_trace_modules()

   return {
      modules = current_modules
   } as lsp.SetTraceModulesResult
end

function MiscHandlers:_on_hover(params:lsp.Method.Params):any
   local pos = params.position as lsp.Position
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)
   local doc <const> = self._document_manager:try_get(file_path)

   tracing.trace(_module_name, "Received request for hover at position: {@}", {pos})
   local node_info = tree_sitter_helper.guess_leaf_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return {
         contents = { "Unknown Token:", " Unable to determine what token is under cursor " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character),
         },
      }
   end

   local env = self._build_handler:get_env()

   local tks: {string} = {}
   if node_info.type == "identifier" then
      -- parent types that show up with multiparts
      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      local tr <const> = env.reporter and env.reporter:get_report()

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
                     local type_str <const> = lsp_formatter.show_type(node_info, type_info, doc, env)
                     return {
                        contents = type_str,
                        range = {
                           start = lsp.position(pos.line, pos.character),
                           ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
                        },
                     }
                  end
               end
            end
         end
      end

      return {
         contents = { node_info.parent_type, ":", node_info.type },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      }
   end

   local type_info = teal_helper.type_information_for_tokens(doc, tks, pos.line, pos.character, env)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type info based on token", {})
      return {
         contents = { node_info.source .. ":", " No type_info found " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      }
   end

   tracing.trace(_module_name, "Successfully found type_info: {@}", {type_info})

   local type_str <const> = lsp_formatter.show_type(node_info, type_info, doc, env)
   return {
      contents = type_str,
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
      },
   }
end

function MiscHandlers:_on_type_definition(params:lsp.Method.Params):any
   local pos = params.position as lsp.Position
   local td <const> = params.textDocument as lsp.TextDocument
   local uri = Uri.parse(td.uri)
   local file_path = Uri.to_file_path(uri)
   local doc <const> = self._document_manager:try_get(file_path)

   tracing.trace(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = tree_sitter_helper.guess_leaf_info_at(doc, pos.line, pos.character)

   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end

   tracing.trace(_module_name, "Received request for on_type_definition at position: {@}", {pos})

   local tks: {string} = {}
   if node_info.type == "identifier" then
      -- parent types that show up with multiparts
      if indexable_parent_types[node_info.parent_type] then
         tks = split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't get type definition for anything that isn't an identifier: {}", {node_info.type})
      return nil
   end

   local env = self._build_handler:get_env()

   -- For type definition, we always want the type information, not the variable declaration
   local type_info = teal_helper.type_information_for_tokens(doc, tks, pos.line, pos.character, env)

   if not type_info or type_info.file == nil then
      return nil
   end

   tracing.trace(_module_name, "[on_type_definition] Found type type_info: {}", {type_info})

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

   return {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(type_info.y - 1, type_info.x - 1),
         ["end"] = lsp.position(type_info.y - 1, type_info.x - 1 + #(type_info.str or "")),
      },
   }
end

function MiscHandlers:_add_handler(name:lsp.Method.Name, handler:function(MiscHandlers, lsp.Method.Params):any)
   self._lsp_events_manager:set_handler(name, function(params:lsp.Method.Params):any return handler(self, params) end)
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
   self:_add_handler("textDocument/typeDefinition", self._on_type_definition)

   self:_add_handler("workspace/diagnostic", self._on_workspace_diagnostic)

   -- Debug-only handlers
   if debug_flags.extra_debugging_enabled then
      self:_add_handler("teal/setTraceModules", self._on_set_trace_modules)
   end
end

class.setup(MiscHandlers, "MiscHandlers", {
})

return MiscHandlers
