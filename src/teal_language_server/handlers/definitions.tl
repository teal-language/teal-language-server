local _module_name = "handlers.definitions"

local handler_helper <const> = require("teal_language_server.handlers.handler_helper")
local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local Document <const> = require("teal_language_server.analysis.document")
local ServerState <const> = require("teal_language_server.server_state")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local LspEventsManager <const> = require("teal_language_server.lsp.events_manager")
local Path <const> = require("teal_language_server.util.path")
local Uri <const> = require("teal_language_server.util.uri")
local lsp <const> = require("teal_language_server.lsp.protocol")
local logging <const> = require("teal_language_server.logging")
local class <const> = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local record DefinitionHandlers
   _document_manager: DocumentManager
   _server_state: ServerState
   _lsp_reader_writer: LspReaderWriter
   _lsp_events_manager: LspEventsManager

   metamethod __call: function(self: DefinitionHandlers, lsp_events_manager: LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager): DefinitionHandlers
end

function DefinitionHandlers:__init(lsp_events_manager: LspEventsManager, lsp_reader_writer: LspReaderWriter, server_state: ServerState, document_manager: DocumentManager)
   self._lsp_events_manager = lsp_events_manager
   self._lsp_reader_writer = lsp_reader_writer
   self._server_state = server_state
   self._document_manager = document_manager
end

-- Resolves a (possibly relative) source file path to a Uri and replies to `id`
-- with an LSP Location pointing at the 1-indexed (y, x). Returns true if a
-- location was sent, false if `file` was nil (no location available).
function DefinitionHandlers:_send_location(id: integer, doc: Document, file: string, y: integer, x: integer): boolean
   if file == nil or y == nil or x == nil then
      return false
   end

   local file_uri: Uri

   if #file == 0 or file == doc.uri.path then
      file_uri = doc.uri
   else
      local full_path: string

      if Path(file):is_absolute() then
         full_path = file
      else
         full_path = self._server_state.teal_project_root_dir.value .. "/" .. file
      end

      file_uri = Uri.uri_from_path(Path(full_path).value)
   end

   self._lsp_reader_writer:send_rpc(id, {
      uri = Uri.tostring(file_uri),
      range = {
         start = lsp.position(y - 1, x - 1),
         ["end"] = lsp.position(y - 1, x - 1),
      },
   })
   return true
end

-- "Go to definition": jump to where the *symbol* under the cursor is declared.
-- For a base symbol this is its declaration site; for a field access it is where
-- that field's type is declared (which works across files for record/function
-- fields), falling back to the enclosing record's declaration when the field's
-- type has no position (e.g. primitives like boolean).
function DefinitionHandlers:_on_definition(params: lsp.Method.Params, id: integer): nil
   local pos <const> = params.position as lsp.Position
   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   logger:trace("Received request for on_definition at position: %s", pos)

   if node_info.kind ~= "identifier" then
      logger:warning("Can't go to definition of anything that isn't an identifier atm: %s", node_info.kind)
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   -- token_chain_raw keeps `self` literal so it resolves as a real in-scope
   -- parameter symbol, rather than depending on self_type detection, which is
   -- only set for named methods and not for function literals.
   local tks = node_info.token_chain_raw

   -- Base symbol (e.g. `apple`, `self`, `TestType_mt`): go to its declaration.
   if #tks == 1 then
      local decl_y, decl_x = doc:symbol_declaration_position(tks[1], pos.line, pos.character)
      if decl_y ~= nil and self:_send_location(id, doc, doc.uri.path, decl_y, decl_x) then
         return
      end
      -- Not a tracked symbol (e.g. a global or a type name used as a value):
      -- fall back to where its type is declared so we don't regress those.
   end

   -- Field access (e.g. `self.test_value`, `mod.func`): the field's type carries
   -- the declaration position for record/function fields.
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)
   if type_info and self:_send_location(id, doc, type_info.file, type_info.y, type_info.x) then
      logger:trace("[on_definition] Resolved via field/type position")
      return
   end

   -- The field's type has no position (e.g. a primitive). Fall back to the
   -- enclosing record's declaration.
   if #tks > 1 then
      local parent_tks: {string} = {}
      for i = 1, #tks - 1 do parent_tks[i] = tks[i] end
      local parent_info = doc:type_information_for_tokens(parent_tks, pos.line, pos.character)
      if parent_info and self:_send_location(id, doc, parent_info.file, parent_info.y, parent_info.x) then
         logger:trace("[on_definition] Resolved via enclosing record position")
         return
      end
   end

   self._lsp_reader_writer:send_rpc(id, nil)
end

-- "Go to type definition": jump to where the *type* of the symbol under the
-- cursor is declared. This is the behavior `textDocument/definition` previously
-- had.
function DefinitionHandlers:_on_type_definition(params: lsp.Method.Params, id: integer): nil
   local pos <const> = params.position as lsp.Position
   local node_info, doc = handler_helper.get_node_info(self._document_manager, params, pos)
   if node_info == nil then
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   logger:trace("Received request for on_type_definition at position: %s", pos)

   if node_info.kind ~= "identifier" then
      logger:warning("Can't go to type definition of anything that isn't an identifier atm: %s", node_info.kind)
      self._lsp_reader_writer:send_rpc(id, nil)
      return
   end

   local tks = node_info.token_chain_raw
   local type_info = doc:type_information_for_tokens(tks, pos.line, pos.character)

   logger:trace("[on_type_definition] Found type type_info: %s", type_info)

   if not type_info or not self:_send_location(id, doc, type_info.file, type_info.y, type_info.x) then
      self._lsp_reader_writer:send_rpc(id, nil)
   end
end

function DefinitionHandlers:initialize()
   self._lsp_events_manager:set_handler("textDocument/definition", function(params: lsp.Method.Params, id: integer) self:_on_definition(params, id) end)
   self._lsp_events_manager:set_handler("textDocument/typeDefinition", function(params: lsp.Method.Params, id: integer) self:_on_type_definition(params, id) end)
end

class.setup(DefinitionHandlers, "DefinitionHandlers", {})

return DefinitionHandlers
