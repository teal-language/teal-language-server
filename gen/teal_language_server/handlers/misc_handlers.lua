local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local math = _tl_compat and _tl_compat.math or math; local string = _tl_compat and _tl_compat.string or string; local _module_name = "misc_handlers"

local DocumentSyncHandlers = require("teal_language_server.handlers.document_sync")
local LanguageFeatureHandlers = require("teal_language_server.handlers.language_features")
local DefinitionHandlers = require("teal_language_server.handlers.definitions")
local EnvUpdater = require("teal_language_server.analysis.env_updater")
local args_parser = require("teal_language_server.args_parser")
local TraceStream = require("teal_language_server.logging.trace_stream")
local DocumentManager = require("teal_language_server.analysis.document_manager")
local ServerState = require("teal_language_server.server_state")
local LspReaderWriter = require("teal_language_server.lsp.reader_writer")
local Path = require("teal_language_server.util.path")
local Uri = require("teal_language_server.util.uri")
local lsp = require("teal_language_server.lsp.protocol")
local LspEventsManager = require("teal_language_server.lsp.events_manager")
local uv = require("luv")
local asserts = require("teal_language_server.util.asserts")
local tracing = require("teal_language_server.logging.tracing")
local class = require("teal_language_server.util.class")

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

function MiscHandlers:_add_handler(name, handler)
   self._lsp_events_manager:set_handler(name, function(params, id) handler(self, params, id) end)
end

function MiscHandlers:initialize()
   self:_add_handler("initialize", self._on_initialize)
   self:_add_handler("initialized", self._on_initialized)

   DocumentSyncHandlers(self._lsp_events_manager, self._document_manager, self._env_updater):initialize()
   LanguageFeatureHandlers(self._lsp_events_manager, self._lsp_reader_writer, self._document_manager):initialize()
   DefinitionHandlers(self._lsp_events_manager, self._lsp_reader_writer, self._server_state, self._document_manager):initialize()
end

class.setup(MiscHandlers, "MiscHandlers", {})


return MiscHandlers
