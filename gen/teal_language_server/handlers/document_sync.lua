local _module_name = "document_sync_handlers"

local EnvUpdater = require("teal_language_server.analysis.env_updater")
local DocumentManager = require("teal_language_server.analysis.document_manager")
local LspEventsManager = require("teal_language_server.lsp.events_manager")
local Uri = require("teal_language_server.util.uri")
local lsp = require("teal_language_server.lsp.protocol")
local logging = require("teal_language_server.logging")
local class = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local DocumentSyncHandlers = {}







function DocumentSyncHandlers:__init(lsp_events_manager, document_manager, env_updater)
   self._lsp_events_manager = lsp_events_manager
   self._document_manager = document_manager
   self._env_updater = env_updater
end

function DocumentSyncHandlers:_on_did_open(params)
   local td = params.textDocument
   self._document_manager:open(Uri.parse(td.uri), td.text, td.version):
   process_and_publish_results()
end

function DocumentSyncHandlers:_on_did_close(params)
   local td = params.textDocument
   self._document_manager:close(Uri.parse(td.uri))
end

function DocumentSyncHandlers:_on_did_save(params)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))

   if not doc then
      logger:warning("Unable to find document: %s")
      return
   end

   doc:update_text(params.text, td.version)



   logger:debug("detected document file saved - enqueuing full env update")
   self._env_updater:schedule_env_update()
end

function DocumentSyncHandlers:_on_did_change(params)
   local td = params.textDocument
   local doc = self._document_manager:get(Uri.parse(td.uri))
   if not doc then
      logger:warning("Unable to find document: %s", td.uri)
      return
   end
   local changes = params.contentChanges
   doc:update_text(changes[1].text, td.version)
   doc:process_and_publish_results()
end

function DocumentSyncHandlers:initialize()
   self._lsp_events_manager:set_handler("textDocument/didOpen", function(params, _id) self:_on_did_open(params) end)
   self._lsp_events_manager:set_handler("textDocument/didClose", function(params, _id) self:_on_did_close(params) end)
   self._lsp_events_manager:set_handler("textDocument/didSave", function(params, _id) self:_on_did_save(params) end)
   self._lsp_events_manager:set_handler("textDocument/didChange", function(params, _id) self:_on_did_change(params) end)
end

class.setup(DocumentSyncHandlers, "DocumentSyncHandlers", {})

return DocumentSyncHandlers
