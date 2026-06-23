local _module_name = "handlers.document_sync"

local EnvUpdater <const> = require("teal_language_server.analysis.env_updater")
local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local LspEventsManager <const> = require("teal_language_server.lsp.events_manager")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local logging <const> = require("teal_language_server.logging")
local class <const> = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local record DocumentSyncHandlers
   _document_manager: DocumentManager
   _lsp_events_manager: LspEventsManager
   _env_updater: EnvUpdater

   metamethod __call: function(self: DocumentSyncHandlers, lsp_events_manager: LspEventsManager, document_manager: DocumentManager, env_updater: EnvUpdater): DocumentSyncHandlers
end

function DocumentSyncHandlers:__init(lsp_events_manager: LspEventsManager, document_manager: DocumentManager, env_updater: EnvUpdater)
   self._lsp_events_manager = lsp_events_manager
   self._document_manager = document_manager
   self._env_updater = env_updater
end

function DocumentSyncHandlers:_on_did_open(params: lsp.Method.Params): nil
   local td <const> = params.textDocument as lsp.TextDocument
   self._document_manager:open(Uri.parse(td.uri), td.text, td.version)
      :process_and_publish_results()
end

function DocumentSyncHandlers:_on_did_close(params: lsp.Method.Params): nil
   local td <const> = params.textDocument as lsp.TextDocument
   self._document_manager:close(Uri.parse(td.uri))
end

function DocumentSyncHandlers:_on_did_save(params: lsp.Method.Params): nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      logger:warning("Unable to find document: %s", td.uri)
      return
   end

   doc:update_text(params.text as string, td.version)
   -- Don't bother calling process_and_publish_results here because this
   -- will happen anyway after the full env update

   logger:debug("detected document file saved - enqueuing full env update")
   self._env_updater:schedule_env_update()
end

function DocumentSyncHandlers:_on_did_change(params: lsp.Method.Params): nil
   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = self._document_manager:get(Uri.parse(td.uri))
   if not doc then
      logger:warning("Unable to find document: %s", td.uri)
      return
   end
   local changes <const> = params.contentChanges as {lsp.TextDocumentContentChangeEvent}
   doc:update_text(changes[1].text as string, td.version)
   doc:process_and_publish_results()
end

function DocumentSyncHandlers:initialize()
   self._lsp_events_manager:set_handler("textDocument/didOpen", function(params: lsp.Method.Params, _id: integer) self:_on_did_open(params) end)
   self._lsp_events_manager:set_handler("textDocument/didClose", function(params: lsp.Method.Params, _id: integer) self:_on_did_close(params) end)
   self._lsp_events_manager:set_handler("textDocument/didSave", function(params: lsp.Method.Params, _id: integer) self:_on_did_save(params) end)
   self._lsp_events_manager:set_handler("textDocument/didChange", function(params: lsp.Method.Params, _id: integer) self:_on_did_change(params) end)
end

class.setup(DocumentSyncHandlers, "DocumentSyncHandlers", {})

return DocumentSyncHandlers
