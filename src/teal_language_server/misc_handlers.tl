local _module_name = "misc_handlers"

-- <imports>
local EnvUpdater <const> = require("teal_language_server.env_updater")
local args_parser <const> = require("teal_language_server.args_parser")
local TraceStream <const> = require("teal_language_server.trace_stream")
local DocumentManager <const> = require("teal_language_server.document_manager")
local ServerState <const> = require("teal_language_server.server_state")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local Path <const> = require("teal_language_server.path")
local Uri <const> = require("teal_language_server.uri")
local lsp <const> = require("teal_language_server.lsp")
local LspEventsManager <const> = require("teal_language_server.lsp_events_manager")
local uv <const> = require("luv")
local asserts <const> = require("teal_language_server.asserts")
local tracing <const> = require("teal_language_server.tracing")
local class <const> = require("teal_language_server.class")
local tl <const> = require("tl")
local lsp_formatter <const> = require("teal_language_server.lsp_formatter")

local record MiscHandlers
   _env_updater: EnvUpdater
   _trace_stream: TraceStream
   _document_manager: DocumentManager
   _server_state: ServerState
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager
   _has_handled_initialize: boolean
   _cl_args: args_parser.CommandLineArgs

   metamethod __call: function(self: MiscHandlers, lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager, trace_stream: TraceStream, args:args_parser.CommandLineArgs, env_updater: EnvUpdater): MiscHandlers
end

function MiscHandlers:__init(lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager, trace_stream: TraceStream, args:args_parser.CommandLineArgs, env_updater: EnvUpdater)
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

function MiscHandlers:_on_initialize(params:lsp.Method.Params, id:integer):nil
   asserts.that(not self._has_handled_initialize)
   self._has_handled_initialize= true
   local root_dir_str:string

   if params.rootUri then
      root_dir_str = Uri.path_from_uri(params.rootUri as string)
   else
      root_dir_str = params.rootPath as string
   end

   local root_path = Path(root_dir_str)
   asserts.that(root_path:exists(), "Expected path to exist at '{}'", root_path.value)

   -- Now that we have the project path, rename log file so it is more discoverable
   -- so we can do project specific debugging more easily
   if self._cl_args.log_mode == "by_proj_path" then
      local pid = math.floor(uv.os_getpid())
      local new_log_name = root_path.value:gsub('[\\/:*?"<>|]+', '_') .. "_" .. tostring(pid)
      self._trace_stream:rename_output_file(new_log_name)
   end

   tracing.info(_module_name, "Received initialize request from client. Teal project dir: {}", {root_path.value})

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

function MiscHandlers:_on_initialized():nil
   tracing.debug(_module_name, "Received 'initialized' notification", {})
end

function MiscHandlers:_on_did_open(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument

   self._document_manager:open(Uri.parse(td.uri), td.text, td.version)
      :process_and_publish_results()
end

function MiscHandlers:_on_did_close(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument
   self._document_manager:close(Uri.parse(td.uri))
end

function MiscHandlers:_on_did_save(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "Unable to find document: {}", {td.uri})
      return
   end

   doc:update_text(params.text as string, td.version)
   -- Don't bother calling process_and_publish_results here because this
   -- will happen anyway after the full env update

   tracing.debug(_module_name, "detected document file saved - enqueuing full env update", {})
   self._env_updater:schedule_env_update()
end

function MiscHandlers:_on_did_change(params:lsp.Method.Params):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))
   if not doc then
      tracing.warning(_module_name, "Unable to find document: {}", {td.uri})
      return
   end
   local changes <const> = params.contentChanges as {lsp.TextDocumentContentChangeEvent}
   doc:update_text(changes[1].text as string, td.version)
   doc:process_and_publish_results()
end

function MiscHandlers:_on_completion(params:lsp.Method.Params, id:integer):nil
   local context = params.context as lsp.CompletionContext

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      tracing.warning(_module_name, "Ignoring completion request given kind: {}", {context.triggerKind})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   -- completion COMPLETELY breaks if you remove the "- 2" or change it
   -- I _think_ it allows teal to create a full representation of the program
   -- so the type checking still works and produces good syntax trees
   local pos = params.position as lsp.Position
   pos.character = pos.character - 2

   tracing.warning(_module_name, "Received request for completion at position: {}", {pos})

   local tks, ends_with_colon <const> = doc:token_at(pos)
   -- local tk = tks[1]
   if #tks == 0 then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local items:{any} = { }
   local type_info = doc:type_information_for_tokens(tks)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.trace(_module_name, "Successfully found type type_info '{}'", {type_info})
      local tr = doc:get_type_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref)
      end

      -- string
      if type_info.t == tl.typecodes.STRING then
         type_info = tr.types[tr.globals["string"]]
      end

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v)
            -- self based access should only show functions
            if ends_with_colon then
               if type_info.t == tl.typecodes.FUNCTION then
                  local args = doc:get_function_args_string(type_info)
                  if #args >= 1 and args[1] == "self" then
                     table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
                  end
               end
            else
               table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
            end
         end

      -- at a table, we might be able to help resolve the keys!
      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys)

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

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items
   })
end

function MiscHandlers:_on_signature_help(params:lsp.Method.Params, id:integer):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))
   local output: lsp_formatter.SignatureHelp = {}

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local pos = params.position as lsp.Position
   pos.character = pos.character - 2

   tracing.warning(_module_name, "Received request for completion at position: {}", {pos})

   local tks, ends_with_colon <const> = doc:token_at(pos)
   if #tks == 0 then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local type_info = doc:type_information_for_tokens(tks)

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
            local func_str = lsp_formatter.create_function_string(type_info.str, args, tks[#tks].tk)
            table.insert(output.signatures, {label = func_str})
         else
            table.insert(output.signatures, {label = type_info.str})
         end
      end
   else
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, tks[#tks].tk)
         table.insert(output.signatures, {label = func_str})
      else
         table.insert(output.signatures, {label = type_info.str})
      end
   end

   tracing.warning(_module_name, "[_on_signature_help] Found type info: {}", {type_info})

   self._lsp_reader_writer:send_rpc(id, output)
end

function MiscHandlers:_on_definition(params:lsp.Method.Params, id:integer):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.trace(_module_name, "[on_definition] No document found for given uri", {})
      return
   end

   local pos <const> = params.position as lsp.Position
   local tks <const> = doc:token_at(pos)
   if #tks == 0 then
      tracing.trace(_module_name, "[on_definition] No token found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local info <const> = doc:type_information_for_tokens(tks)

   if not info or info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_definition] Found type info: {}", {info})

   local file_uri: Uri

   if #info.file == 0 then
      file_uri = doc.uri
   else
      local full_path: string

      if Path(info.file):is_absolute() then
         full_path = info.file
      else
         full_path = self._server_state.teal_project_root_dir.value .. "/" .. info.file
      end

      local file_path = Path(full_path)
      file_uri = Uri.uri_from_path(file_path.value)
   end

   self._lsp_reader_writer:send_rpc(id, {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(info.y - 1, info.x - 1),
         ["end"] = lsp.position(info.y - 1, info.x - 1),
      },
   })
end

function MiscHandlers:_on_hover(params:lsp.Method.Params, id:integer):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "Failed to find document for given params", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end
   local pos <const> = params.position as lsp.Position

   tracing.trace(_module_name, "Received request for hover at position: {}", {pos})

   local tks <const> = doc:token_at(pos)
   if #tks == 0 then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { " No info found " }
      })
      return
   end
   local tk = tks[#tks]
   local token_pos = lsp.position(tk.y, tk.x)
   tracing.trace(_module_name, "Found actual token '{}' at position: '{}'", {tk.tk, token_pos})
   tracing.warning(_module_name, "Attempting to get type information by raw token instead...", {})

   local type_info = doc:type_information_for_tokens(tks)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type info based on token", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { tk.tk .. ":", " No type_info found " },
         range = {
            start = lsp.position(token_pos.line, token_pos.character),
            ["end"] = lsp.position(token_pos.line, token_pos.character + #tk.tk),
         },
      })
      return
   end

   tracing.warning(_module_name, "Successfully found type_info: {}", {type_info})

   local type_str <const> = lsp_formatter.show_type(type_info, doc:get_type_report())
   self._lsp_reader_writer:send_rpc(id, {
      contents = { tk.tk .. ":", type_str },
      range = {
         start = lsp.position(token_pos.line, token_pos.character),
         ["end"] = lsp.position(token_pos.line, token_pos.character + #tk.tk),
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
   self:_add_handler("textDocument/definition", self._on_definition)
   self:_add_handler("textDocument/hover", self._on_hover)
end

class.setup(MiscHandlers, "MiscHandlers", {
})

return MiscHandlers
