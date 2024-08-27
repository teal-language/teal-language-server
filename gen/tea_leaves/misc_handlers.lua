local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "misc_handlers"


local EnvUpdater = require("tea_leaves.env_updater")
local args_parser = require("tea_leaves.args_parser")
local TraceStream = require("tea_leaves.trace_stream")
local DocumentManager = require("tea_leaves.document_manager")
local ServerState = require("tea_leaves.server_state")
local LspReaderWriter = require("tea_leaves.lsp_reader_writer")
local Path = require("tea_leaves.path")
local Uri = require("tea_leaves.uri")
local lsp = require("tea_leaves.lsp")
local LspEventsManager = require("tea_leaves.lsp_events_manager")
local uv = require("luv")
local asserts = require("tea_leaves.asserts")
local tracing = require("tea_leaves.tracing")
local class = require("tea_leaves.class")

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

function MiscHandlers:_on_completion(params, id)
   local context = params.context



   if context.triggerKind ~= 2 then
      tracing.warning(_module_name, "Ignoring completion request given kind: {}", { context.triggerKind })
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local pos = params.position
   pos.character = pos.character - 2

   tracing.info(_module_name, "Received request for completion at position: {}", { pos })

   local tk = doc:token_at(pos)

   if not tk then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local token_pos = lsp.position(tk.y, tk.x)
   tracing.trace(_module_name, "Found actual token {} at position: {}", { tk.tk, token_pos })

   local type_info = doc:type_information_at(token_pos)
   local items = {}

   if not type_info then
      tracing.trace(_module_name, "No type information found at calculated token position {}.  Attempting to get type information by raw token instead.", { token_pos })

      type_info = doc:type_information_for_token(tk)

      if not type_info then
         tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
      end
   end

   if type_info then
      tracing.trace(_module_name, "Successfully found type type_info '{}'", { type_info })

      if type_info.ref then
         local tr, _ = doc:get_type_report()
         local real_type_info = tr.types[type_info.ref]
         if real_type_info.fields then
            for key, _ in pairs(real_type_info.fields) do
               table.insert(items, { label = key })
            end
         else
            tracing.warning(_module_name, "Unable to get fields for ref type", {})
         end
      else
         if type_info.fields then
            for key, _ in pairs(type_info.fields) do
               table.insert(items, { label = key })
            end
         else
            tracing.warning(_module_name, "Unable to get fields for type", {})
         end
      end
   end

   if #items == 0 then
      table.insert(items, { label = "(none)" })
   end

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items,
   })
end

function MiscHandlers:_on_definition(params, id)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.trace(_module_name, "[on_definition] No document found for given uri", {})
      return
   end

   local pos = params.position
   local tk = doc:token_at(pos)
   if not tk then
      tracing.trace(_module_name, "[on_definition] No token found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local token_pos = lsp.position(tk.y, tk.x)
   local info = doc:type_information_at(token_pos)

   if not info or info.file == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.trace(_module_name, "[on_definition] Found type info: {}", { info })

   local file_uri

   if #info.file == 0 then
      file_uri = doc.uri
   else
      local full_path

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

function MiscHandlers:_on_hover(params, id)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "Failed to find document for given params", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end
   local pos = params.position

   tracing.trace(_module_name, "Received request for hover at position: {}", { pos })

   local tk = doc:token_at(pos)
   if not tk then
      tracing.warning(_module_name, "Could not find token at given position", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { " No info found " },
      })
      return
   end
   local token_pos = lsp.position(tk.y, tk.x)
   tracing.trace(_module_name, "Found actual token '{}' at position: '{}'", { tk.tk, token_pos })
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

   tracing.trace(_module_name, "Successfully found type_info: {}", { type_info })

   local type_str = doc:show_type(type_info)
   self._lsp_reader_writer:send_rpc(id, {
      contents = { tk.tk .. ":", type_str },
      range = {
         start = lsp.position(token_pos.line, token_pos.character),
         ["end"] = lsp.position(token_pos.line, token_pos.character + #tk.tk),
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
   self:_add_handler("textDocument/definition", self._on_definition)
   self:_add_handler("textDocument/hover", self._on_hover)
end

class.setup(MiscHandlers, "MiscHandlers", {})


return MiscHandlers
