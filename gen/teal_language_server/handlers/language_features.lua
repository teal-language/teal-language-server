local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; local _module_name = "handlers.language_feature"

local handler_helper = require("teal_language_server.handlers.handler_helper")
local DocumentManager = require("teal_language_server.analysis.document_manager")
local NodeInfo = require("teal_language_server.analysis.node_info")
local LspReaderWriter = require("teal_language_server.lsp.reader_writer")
local LspEventsManager = require("teal_language_server.lsp.events_manager")
local lsp = require("teal_language_server.lsp.protocol")
local logging = require("teal_language_server.logging")
local class = require("teal_language_server.util.class")
local tl = require("tl")
local lsp_formatter = require("teal_language_server.lsp.formatter")

local logger = logging.get_logger(_module_name)

local LanguageFeatureHandlers = {}







function LanguageFeatureHandlers:__init(lsp_events_manager, lsp_reader_writer, document_manager)
   self._lsp_events_manager = lsp_events_manager
   self._lsp_reader_writer = lsp_reader_writer
   self._document_manager = document_manager
end

function LanguageFeatureHandlers:_on_completion(params, id)
   local pos = params.position
   logger:info("Received request for completion at position: %s", pos)



   pos.character = pos.character - 1

   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      logger:trace("No node found at given position")
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   logger:debug("Found node info: %s", node_info)

   local type_info



   if node_info.kind == "dot" or node_info.kind == "colon" then
      type_info = doc:resolve_preceded_type(node_info, pos)


   elseif node_info.kind == "identifier" then

      local tks = node_info.token_chain




      tks[#tks] = nil



      if node_info.in_declaration_position then
         self._lsp_reader_writer:send_rpc(id, nil)
         return
      end

      type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local items = {}

   if not type_info then
      logger:info("Also failed to find type type_info based on token")
   end

   if type_info then
      logger:debug("Successfully found type_info")
      local tr = doc:get_type_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref)
      end


      local was_string_type = type_info.t == tl.typecodes.STRING
      if was_string_type then
         type_info = tr.types[tr.globals["string"]]
      end




      local original_str = type_info.str



      local function is_self_method(fn)
         if fn.t ~= tl.typecodes.FUNCTION or not fn.args or #fn.args < 1 then
            return false
         end
         local first_arg_type = doc:resolve_type_ref(fn.args[1][1])
         return first_arg_type.t == tl.typecodes.SELF or
         ((first_arg_type.t == tl.typecodes.NOMINAL or first_arg_type.t == tl.typecodes.RECORD) and first_arg_type.str == original_str) or
         (was_string_type and first_arg_type.t == tl.typecodes.STRING)
      end

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v)
            local was_added

            if node_info.kind == "colon" then


               local self_method = false
               if type_info.t == tl.typecodes.POLY then
                  for _, ref in ipairs(type_info.types) do
                     if is_self_method(doc:resolve_type_ref(ref)) then
                        self_method = true
                        break
                     end
                  end
               else
                  self_method = is_self_method(type_info)
               end

               if self_method then
                  logger:debug("Adding self method %s", key)
                  table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
                  was_added = true
               else
                  logger:debug("Ignoring method %s with type 0x%08x for type info str %s",
                  key, type_info.t, original_str)
               end
            else
               table.insert(items, { label = key, kind = lsp.typecodes_to_kind[type_info.t] })
               was_added = true
            end

            if not was_added then
               logger:trace("Ignoring field %s", key)
            end
         end


      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys)

         if type_info.enums then
            for _, enum_value in ipairs(type_info.enums) do
               table.insert(items, { label = enum_value, kind = lsp.typecodes_to_kind[type_info.t] })
            end
         end
      else
         logger:info("Unable to get fields for ref type")
      end
   end

   if #items == 0 then
      table.insert(items, { label = "(none)" })
   end

   logger:debug("Sending %d back to client", #items)

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items,
   })
end

function LanguageFeatureHandlers:_on_signature_help(params, id)
   local pos = params.position


   pos.character = pos.character - 1

   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local output = {}
   logger:debug("Got nodeinfo: %s", node_info)

   local type_info

   if node_info.kind == "open_paren" then
      type_info = doc:resolve_preceded_type(node_info, pos)
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   if type_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   output.signatures = {}
   if type_info.t == tl.typecodes.POLY then
      for _, type_ref in ipairs(type_info.types) do
         type_info = doc:resolve_type_ref(type_ref)
         local args = doc:get_function_args_string(type_info)
         if args ~= nil then
            local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
            table.insert(output.signatures, { label = func_str })

         else
            table.insert(output.signatures, { label = type_info.str })
         end
      end
   else
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, { label = func_str })
      else
         table.insert(output.signatures, { label = type_info.str })
      end
   end

   logger:debug("[_on_signature_help] Found type info: %s", type_info)

   if #output.signatures == 0 then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   self._lsp_reader_writer:send_rpc(id, output)
end






local function token_range(node_info)
   return {
      start = lsp.position(node_info.start_y, node_info.start_x),
      ["end"] = lsp.position(node_info.end_y, node_info.end_x),
   }
end

function LanguageFeatureHandlers:_on_hover(params, id)
   local pos = params.position
   logger:trace("Received request for hover at position: %s", pos)
   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos, true)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, {
         contents = { "Unknown Token:", " Unable to determine what token is under cursor " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character),
         },
      })
      return
   end

   local tks = {}
   local quick_type_info
   if node_info.kind == "identifier" then


      if node_info.bypos_y then
         quick_type_info = doc:type_information_for_position(node_info.bypos_y, node_info.bypos_x)
      end

      if quick_type_info == nil then
         tks = node_info.token_chain
      end
   else
      logger:warning("Can't hover over anything that isn't an identifier atm: %s", node_info.kind)
      self._lsp_reader_writer:send_rpc(id, {
         contents = { "Unknown Token:", " Unable to resolve the token under the cursor " },
         range = token_range(node_info),
      })
      return
   end

   local type_info = quick_type_info or doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info then
      logger:warning("Also failed to find type info based on token")
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.source .. ":", " No type_info found " },
         range = token_range(node_info),
      })
      return
   end

   logger:debug("Successfully found type_info: %s", type_info)

   local type_str = lsp_formatter.show_type(node_info, type_info, doc)
   self._lsp_reader_writer:send_rpc(id, {
      contents = type_str,
      range = token_range(node_info),
   })
end

function LanguageFeatureHandlers:initialize()
   self._lsp_events_manager:set_handler("textDocument/completion", function(params, id) self:_on_completion(params, id) end)
   self._lsp_events_manager:set_handler("textDocument/signatureHelp", function(params, id) self:_on_signature_help(params, id) end)
   self._lsp_events_manager:set_handler("textDocument/hover", function(params, id) self:_on_hover(params, id) end)
end

class.setup(LanguageFeatureHandlers, "LanguageFeatureHandlers", {})

return LanguageFeatureHandlers
