local _module_name = "handler_helper"

local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local Document <const> = require("teal_language_server.analysis.document")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local tracing <const> = require("teal_language_server.logging.tracing")

local record handler_helper
   indexable_parent_types: {string:boolean}
end

handler_helper.indexable_parent_types = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true,
}

function handler_helper.split_by_symbols(input: string, self_type: string, stop_at?: string): {string}
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

function handler_helper.get_node_info(document_manager: DocumentManager, params: lsp.Method.Params, pos: lsp.Position): Document.NodeInfo, Document
   local context = params.context as lsp.CompletionContext

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      tracing.warning(_module_name, "Ignoring completion request given kind: {}", {context.triggerKind})
      return nil
   end

   local td <const> = params.textDocument as lsp.TextDocument
   local doc <const> = document_manager:get(Uri.parse(td.uri))

   if not doc then
      tracing.warning(_module_name, "No doc found for completion request", {})
      return nil
   end

   tracing.debug(_module_name, "Looking up node info at position: {@}", {pos})
   local node_info = doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      tracing.warning(_module_name, "Unable to retrieve node info from tree-sitter parser", {})
      return nil
   end
   tracing.debug(_module_name, "Found node info: {@}", {node_info})
   return node_info, doc
end

return handler_helper
