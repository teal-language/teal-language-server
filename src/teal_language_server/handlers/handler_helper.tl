local _module_name = "handlers.handler_helper"

local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local Document <const> = require("teal_language_server.analysis.document")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local logging <const> = require("teal_language_server.logging")

local logger = logging.get_logger(_module_name)

local record handler_helper
   indexable_parent_types: {string:boolean}
end

handler_helper.indexable_parent_types = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true,
}

-- An explicit completion invocation, as opposed to a trigger-character-driven
-- one: either the client sent no context at all (never carries a trigger
-- character; older clients and simple integrations omit the field entirely) or
-- it used the LSP "Invoked" kind (e.g. Zed, which sends triggerKind=Invoked for
-- typed text and explicit requests alike).
function handler_helper.is_invoked_completion(params: lsp.Method.Params): boolean
   local context = params.context as lsp.CompletionContext
   return context == nil
      or context.triggerKind == lsp.completion_trigger_kind.Invoked
end

function handler_helper.get_node_info(document_manager: DocumentManager, params: lsp.Method.Params, pos: lsp.Position): Document.NodeInfo, Document
   local context = params.context as lsp.CompletionContext

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter
      and context.triggerKind ~= lsp.completion_trigger_kind.Invoked then
      logger:info("Ignoring completion request given kind: %s", context.triggerKind)
      return nil
   end

   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = document_manager:get(Uri.parse(td.uri))

   if not doc then
      logger:warning("No doc found for completion request")
      return nil
   end

   logger:debug("Looking up node info at position: %s", pos)
   local node_info = doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      logger:info("Unable to retrieve node info from tree-sitter parser")
      -- hand the document back so callers can retry with a different lookup
      -- strategy where no tree-sitter leaf covers the position
      return nil, doc
   end
   logger:debug("Found node info: %s", node_info)
   return node_info, doc
end

return handler_helper
