local _module_name = "language_feature_handlers"

local handler_helper <const> = require("teal_language_server.handlers.handler_helper")
local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local LspEventsManager <const> = require("teal_language_server.lsp.events_manager")
local lsp <const> = require("teal_language_server.lsp.protocol")
local tracing <const> = require("teal_language_server.logging.tracing")
local class <const> = require("teal_language_server.util.class")
local tl <const> = require("tl")
local lsp_formatter <const> = require("teal_language_server.lsp.formatter")

local record LanguageFeatureHandlers
   _document_manager: DocumentManager
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager

   metamethod __call: function(self: LanguageFeatureHandlers, lsp_events_manager: LspEventsManager, lsp_reader_writer: LspReaderWriter, document_manager: DocumentManager): LanguageFeatureHandlers
end

function LanguageFeatureHandlers:__init(lsp_events_manager: LspEventsManager, lsp_reader_writer: LspReaderWriter, document_manager: DocumentManager)
   self._lsp_events_manager = lsp_events_manager
   self._lsp_reader_writer = lsp_reader_writer
   self._document_manager = document_manager
end

function LanguageFeatureHandlers:_on_completion(params: lsp.Method.Params, id: integer): nil
   local pos = params.position as lsp.Position
   tracing.info(_module_name, "Received request for completion at position: {@}", {pos})

   -- Subtract one since neovim passes the character where the cursor is, which is after the '.' / ':'
   -- and this position doesn't exist in the doc so can lead to tree sitter query fails
   pos.character = pos.character - 1

   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      tracing.trace(_module_name, "No node found at given position", {})
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   tracing.debug(_module_name, "Found node info: {@}", {node_info})

   local tks: {string}

   -- literally at the . or : and are trying to autocomplete
   -- preceded_by should have everything we need in it.
   if node_info.type == "." or node_info.type == ":" then
      tks = handler_helper.split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.debug(_module_name, "Received request for completion at character: {@}", {tks})

   -- completion request in the middle of a word like in "node_info.par" while typing "parent_source"
   elseif node_info.type == "identifier" then
      -- the types that we would need to index into to get type info from
      if handler_helper.indexable_parent_types[node_info.parent_type] then
         tks = handler_helper.split_by_symbols(node_info.parent_source, node_info.self_type)
      else
         tks = handler_helper.split_by_symbols(node_info.source, node_info.self_type)
      end

      -- takes it back to the just after the first dot, then does completion
      -- if there's only one symbol, will return an empty list and type_information_for_tokens will just
      -- show what's in scope
      tks[#tks] = nil

      -- trying to define something new, probably don't want the in-scope thing to popup
      -- we could probably help complete simple types
      if node_info.parent_type == "var" or
         node_info.parent_type == "simple_type" or
         node_info.parent_type == "table_type" then
         self._lsp_reader_writer:send_rpc(id, nil)
         return
      end
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local items:{any} = { }
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type type_info based on token", {})
   end

   if type_info then
      tracing.debug(_module_name, "Successfully found type_info {@}", {type_info})
      local tr = doc:get_type_report()

      if type_info.ref then
         type_info = doc:resolve_type_ref(type_info.ref)
      end

      -- string
      local was_string_type = type_info.t == tl.typecodes.STRING
      if was_string_type then
         type_info = tr.types[tr.globals["string"]]
      end

      -- this seemed to be the best way to compare the first arg with itself when comparing ":",
      -- sometimes the types come in as nominal and don't resolve all the way back, so the name is
      -- what seems to work the most reliably
      local original_str = type_info.str

      if type_info.fields then
         for key, v in pairs(type_info.fields) do
            type_info = doc:resolve_type_ref(v)
            local was_added:boolean
            -- self based access should only show functions
            if node_info.type == ":" then
               if type_info.t == tl.typecodes.FUNCTION then
                  -- local args = doc:get_function_args_string(type_info)
                  if type_info.args and #type_info.args >= 1 then
                     local first_arg_type = doc:resolve_type_ref(type_info.args[1][1])
                     if first_arg_type.t == tl.typecodes.SELF
                        or ((first_arg_type.t == tl.typecodes.NOMINAL or first_arg_type.t == tl.typecodes.RECORD) and first_arg_type.str == original_str)
                        or (was_string_type and first_arg_type.t == tl.typecodes.STRING) then
                        tracing.debug(_module_name, "Adding self method {}", {key})
                        table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
                        was_added = true
                     else
                        tracing.debug(_module_name, "Ignoring method {} with arg type {0x%08x}, type info str {}, first arg str {}", {
                           key, first_arg_type.t, original_str, first_arg_type.str})
                     end
                  end
               end
            else
               table.insert(items, {label = key, kind = lsp.typecodes_to_kind[type_info.t]})
               was_added = true
            end

            if not was_added then
               tracing.trace(_module_name, "Ignoring field {}", {key})
            end
         end

      -- at a table, we might be able to help resolve the keys!
      elseif type_info.keys then
         type_info = doc:resolve_type_ref(type_info.keys)

         if type_info.enums then
            for _, enum_value in ipairs(type_info.enums) do
               table.insert(items, {label = enum_value, kind = lsp.typecodes_to_kind[type_info.t]})
            end
         end
      else
         tracing.warning(_module_name, "Unable to get fields for ref type", {})
      end
   end

   if #items == 0 then
      table.insert(items, {label = "(none)"})
   end

   tracing.debug(_module_name, "Sending {} back to client", {#items})

   self._lsp_reader_writer:send_rpc(id, {
      isIncomplete = false,
      items = items
   })
end

function LanguageFeatureHandlers:_on_signature_help(params: lsp.Method.Params, id: integer): nil
   local pos = params.position as lsp.Position

   -- Subtract one to get function identifier instead of bracket
   pos.character = pos.character - 1

   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local output: lsp_formatter.SignatureHelp = {}
   tracing.debug(_module_name, "Got nodeinfo: {}", {node_info})

   local tks: {string}

   if node_info.type == "(" then
      tks = handler_helper.split_by_symbols(node_info.preceded_by, node_info.self_type)
      tracing.debug(_module_name, "Received request for signature help at character: {}", {tks})
   else
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

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
            table.insert(output.signatures, {label = func_str})

         else
            table.insert(output.signatures, {label = type_info.str})
         end
      end
   else
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         local func_str = lsp_formatter.create_function_string(type_info.str, args, node_info.preceded_by)
         table.insert(output.signatures, {label = func_str})
      else
         table.insert(output.signatures, {label = type_info.str})
      end
   end

   tracing.debug(_module_name, "[_on_signature_help] Found type info: {}", {type_info})

   if #output.signatures == 0 then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   self._lsp_reader_writer:send_rpc(id, output)
end

function LanguageFeatureHandlers:_on_hover(params: lsp.Method.Params, id: integer): nil
   local pos <const> = params.position as lsp.Position
   tracing.trace(_module_name, "Received request for hover at position: {@}", {pos})
   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
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

   local tks: {string} = {}
   if node_info.type == "identifier" then
      -- parent types that show up with multiparts
      if handler_helper.indexable_parent_types[node_info.parent_type] then
         tks = handler_helper.split_by_symbols(node_info.parent_source, node_info.self_type, node_info.source)
      else
         tks = handler_helper.split_by_symbols(node_info.source, node_info.self_type)
      end
   else
      tracing.warning(_module_name, "Can't hover over anything that isn't an identifier atm: {}", {node_info.type})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.parent_type, ":", node_info.type },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   if not type_info then
      tracing.warning(_module_name, "Also failed to find type info based on token", {})
      self._lsp_reader_writer:send_rpc(id, {
         contents = { node_info.source .. ":", " No type_info found " },
         range = {
            start = lsp.position(pos.line, pos.character),
            ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
         },
      })
      return
   end

   tracing.debug(_module_name, "Successfully found type_info: {@}", {type_info})

   local type_str <const> = lsp_formatter.show_type(node_info, type_info, doc)
   self._lsp_reader_writer:send_rpc(id, {
      contents = type_str,
      range = {
         start = lsp.position(pos.line, pos.character),
         ["end"] = lsp.position(pos.line, pos.character + #node_info.source),
      },
   })
end

function LanguageFeatureHandlers:initialize()
   self._lsp_events_manager:set_handler("textDocument/completion", function(params: lsp.Method.Params, id: integer) self:_on_completion(params, id) end)
   self._lsp_events_manager:set_handler("textDocument/signatureHelp", function(params: lsp.Method.Params, id: integer) self:_on_signature_help(params, id) end)
   self._lsp_events_manager:set_handler("textDocument/hover", function(params: lsp.Method.Params, id: integer) self:_on_hover(params, id) end)
end

class.setup(LanguageFeatureHandlers, "LanguageFeatureHandlers", {})

return LanguageFeatureHandlers
