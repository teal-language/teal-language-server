local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "handler_helper"

local DocumentManager = require("teal_language_server.analysis.document_manager")
local Document = require("teal_language_server.analysis.document")
local Uri = require("teal_language_server.util.uri")
local lsp = require("teal_language_server.lsp.protocol")
local logging = require("teal_language_server.logging")

local logger = logging.get_logger(_module_name)

local handler_helper = {}



handler_helper.indexable_parent_types = {
   ["index"] = true,
   ["method_index"] = true,
   ["function_name"] = true,
}

function handler_helper.split_by_symbols(input, self_type, stop_at)
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

function handler_helper.get_node_info(document_manager, params, pos)
   local context = params.context

   if context and context.triggerKind ~= lsp.completion_trigger_kind.TriggerCharacter then
      logger:warning("Ignoring completion request given kind: %s", context.triggerKind)
      return nil
   end

   local td = params.textDocument
   local doc = document_manager:get(Uri.parse(td.uri))

   if not doc then
      logger:warning("No doc found for completion request")
      return nil
   end

   logger:debug("Looking up node info at position: %s")
   local node_info = doc:tree_sitter_token(pos.line, pos.character)
   if node_info == nil then
      logger:warning("Unable to retrieve node info from tree-sitter parser")
      return nil
   end
   logger:debug("Found node info: %s", node_info)
   return node_info, doc
end

return handler_helper
