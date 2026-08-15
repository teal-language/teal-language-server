local _module_name = "handlers.handler_helper"

local DocumentManager = require("teal_language_server.analysis.document_manager")
local Document = require("teal_language_server.analysis.document")
local NodeInfo = require("teal_language_server.analysis.node_info")
local Uri = require("teal_language_server.util.uri")
local lsp = require("teal_language_server.lsp.protocol")
local logging = require("teal_language_server.logging")

local logger = logging.get_logger(_module_name)

local handler_helper = {}





function handler_helper.get_node_info(document_manager, params, pos, at_name)
   local context = params.context

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      logger:info("Ignoring completion request given kind: %s", context.triggerKind)
      return nil
   end

   local td = params.textDocument
   local doc = document_manager:get(Uri.parse(td.uri))

   if not doc then
      logger:warning("No doc found for completion request")
      return nil
   end

   logger:debug("Looking up node info at position: %s", pos)
   local node_info = at_name and
   doc:tree_sitter_name_token(pos.line, pos.character) or
   doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      logger:info("Unable to retrieve node info from tree-sitter parser")
      return nil
   end
   logger:debug("Found node info: %s", node_info)
   return node_info, doc
end

return handler_helper
