local _module_name = "misc_handlers"

-- <imports>
local EnvUpdater <const> = require("tea_leaves.env_updater")
local args_parser <const> = require("tea_leaves.args_parser")
local TraceStream <const> = require("tea_leaves.trace_stream")
local DocumentManager <const> = require("tea_leaves.document_manager")
local ServerState <const> = require("tea_leaves.server_state")
local LspReaderWriter <const> = require("tea_leaves.lsp_reader_writer")
local Path <const> = require("tea_leaves.path")
local Uri <const> = require("tea_leaves.uri")
local lsp <const> = require("tea_leaves.lsp")
local LspEventsManager <const> = require("tea_leaves.lsp_events_manager")
local uv <const> = require("luv")
local asserts <const> = require("tea_leaves.asserts")
local tracing <const> = require("tea_leaves.tracing")
local class <const> = require("tea_leaves.class")

local record MiscHandlers
   _env_updater: EnvUpdater
   _trace_stream: TraceStream
   _document_manager: DocumentManager
   _server_state: ServerState
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager
   _has_handled_initialize:boolean
   _cl_args:args_parser.CommandLineArgs

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

   -- triggerKind 1 = manual invocation (do we need to handle this?)
   -- triggerKind 3 = "Completion was re-triggered as the current completion list is incomplete."
   if context.triggerKind ~= 2 then
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

   local pos = params.position as lsp.Position
   pos.character = pos.character - 2

   tracing.info(_module_name, "Received request for completion at position: {}", {pos})

   local tk <const> = doc:token_at(pos)

   if not tk then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local token_pos = lsp.position(tk.y, tk.x)
   tracing.trace(_module_name, "Found actual token {} at position: {}", {tk.tk, token_pos})

   local type_info = doc:type_information_at(token_pos)
   local items:{any} = { }

   if not type_info then
      tracing.trace(_module_name, "No type information found at calculated token position {}.  Attempting to get type information by raw token instead.", {token_pos})

      type_info = doc:type_information_for_token(tk)

      if not type_info then
         tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
      end
   end

   if type_info then
      tracing.trace(_module_name, "Successfully found type type_info '{}'", {type_info})

      if type_info.ref then
         local tr, _ = doc:get_type_report()
         local real_type_info = tr.types[type_info.ref]
         if real_type_info.fields then
            for key, _ in pairs(real_type_info.fields) do
               table.insert(items, {label = key})
            end
         else
            tracing.warning(_module_name, "Unable to get fields for ref type", {})
         end
      else
         if type_info.fields then
            for key, _ in pairs(type_info.fields) do
               table.insert(items, {label = key})
            end
         else
            tracing.warning(_module_name, "Unable to get fields for type", {})
         end
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

function MiscHandlers:_on_definition(params:lsp.Method.Params, id:integer):nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.trace(_module_name, "[on_definition] No document found for given uri", {})
      return
   end

   local pos <const> = params.position as lsp.Position
   local tk <const> = doc:token_at(pos)
   if not tk then
      tracing.trace(_module_name, "[on_definition] No token found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local token_pos = lsp.position(tk.y, tk.x)
   local info <const> = doc:type_information_at(token_pos)

   if not info or info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_definition] Found type info: {}", {info})

   local file_uri: Uri

   if #info.file == 0 then
      file_uri = doc.uri
   else
      local full_path:string

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

   local tk <const> = doc:token_at(pos)
   if not tk then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { " No info found " }
      })
      return
   end
   local token_pos = lsp.position(tk.y, tk.x)
   tracing.trace(_module_name, "Found actual token '{}' at position: '{}'", {tk.tk, token_pos})
   local type_info = doc:type_information_at(token_pos)
   if not type_info then
      tracing.warning(_module_name, "No type information found at calculated token position.  Attempting to get type information by raw token instead...", {})

      type_info = doc:type_information_for_token(tk)

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
   end

   tracing.trace(_module_name, "Successfully found type_info: {}", {type_info})

   local type_str <const> = doc:show_type(type_info)
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
   self:_add_handler("textDocument/definition", self._on_definition)
   self:_add_handler("textDocument/hover", self._on_hover)
end

class.setup(MiscHandlers, "MiscHandlers", {
})

return MiscHandlers
