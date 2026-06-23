local _module_name = "handlers.misc_handlers"

local DocumentSyncHandlers <const> = require("teal_language_server.handlers.document_sync")
local LanguageFeatureHandlers <const> = require("teal_language_server.handlers.language_features")
local DefinitionHandlers <const> = require("teal_language_server.handlers.definitions")
local EnvUpdater <const> = require("teal_language_server.analysis.env_updater")
local args_parser <const> = require("teal_language_server.args_parser")
local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local ServerState <const> = require("teal_language_server.server_state")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local Path <const> = require("teal_language_server.util.path")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local LspEventsManager <const> = require("teal_language_server.lsp.events_manager")
local asserts <const> = require("teal_language_server.util.asserts")
local logging <const> = require("teal_language_server.logging")
local uv <const> = require("luv")
local class <const> = require("teal_language_server.util.class")
local LogFileHandler = require("teal_language_server.log_file")

local logger = logging.get_logger(_module_name)

local record MiscHandlers
   _env_updater: EnvUpdater
   _document_manager: DocumentManager
   _server_state: ServerState
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager
   _has_handled_initialize: boolean
   _cl_args: args_parser.CommandLineArgs
   _log_file: LogFileHandler.LogFile

   metamethod __call: function(self: MiscHandlers, lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager, args:args_parser.CommandLineArgs, log_file: LogFileHandler.LogFile, env_updater: EnvUpdater): MiscHandlers
end

function MiscHandlers:__init(lsp_events_manager:LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager, args:args_parser.CommandLineArgs, log_file: LogFileHandler.LogFile, env_updater: EnvUpdater)
   asserts.is_not_nil(env_updater)

   self._document_manager = document_manager
   self._server_state = server_state
   self._lsp_reader_writer = lsp_reader_writer
   self._lsp_events_manager = lsp_events_manager
   self._has_handled_initialize = false
   self._cl_args = args
   self._log_file = log_file
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

   if self._cl_args.log_mode == "by_proj_path" and self._log_file then
      local pid = math.floor(uv.os_getpid())
      local new_log_name = root_path.value:gsub('[\\/:*?"<>|]+', '_') .. "_" .. tostring(pid)
      self._log_file:rename_output_file(new_log_name)
   end

   logger:info("Received initialize request from client. Teal project dir: %s", root_path.value)

   self._server_state:initialize(root_path)
   self._env_updater:initialize()

   logger:trace("Sending initialize response message...")

   self._lsp_reader_writer:send_rpc(id, {
      capabilities = self._server_state.capabilities,
      serverInfo = {
         name = self._server_state.name,
         version = self._server_state.version,
      },
   })
end

function MiscHandlers:_on_initialized():nil
   logger:debug("Received 'initialized' notification")
end

function MiscHandlers:_add_handler(name:lsp.Method.Name, handler:function(MiscHandlers, lsp.Method.Params, integer):nil)
   self._lsp_events_manager:set_handler(name, function(params:lsp.Method.Params, id:integer) handler(self, params, id) end)
end

function MiscHandlers:initialize()
   self:_add_handler("initialize", self._on_initialize)
   self:_add_handler("initialized", self._on_initialized)

   DocumentSyncHandlers(self._lsp_events_manager, self._document_manager, self._env_updater):initialize()
   LanguageFeatureHandlers(self._lsp_events_manager, self._lsp_reader_writer, self._document_manager):initialize()
   DefinitionHandlers(self._lsp_events_manager, self._lsp_reader_writer, self._server_state, self._document_manager):initialize()
end

class.setup(MiscHandlers, "MiscHandlers", {
})

return MiscHandlers
