local _module_name = "diagnostics_publisher"

-- <imports>
local BuildHandler <const> = require("teal_language_server.build_handler")
local ModuleInfo <const> = require("teal_language_server.module_info")
local class <const> = require("teal_language_server.class")
local lusc <const> = require("lusc")
local OpenDocumentRegistry <const> = require("teal_language_server.open_document_registry")
local uv <const> = require("luv")
local tracing <const> = require("teal_language_server.tracing")
local asserts <const> = require("teal_language_server.asserts")
local ModuleInfoManager <const> = require("teal_language_server.module_info_manager")
local Uri <const> = require("teal_language_server.uri")
local lsp <const> = require("teal_language_server.lsp")
local LspReaderWriter <const> = require("teal_language_server.lsp_reader_writer")
local DiagnosticsHelper <const> = require("teal_language_server.diagnostics_helper")

local record DiagnosticsPublisher
   _module_info_manager: ModuleInfoManager
   _root_nursery:lusc.Nursery
   _change_detected: lusc.StickyEvent
   _build_handler: BuildHandler
   _open_document_registry: OpenDocumentRegistry
   _lsp_reader_writer: LspReaderWriter
   _diagnostics_helper: DiagnosticsHelper

   metamethod __call: function(
      self: DiagnosticsPublisher, root_nursery:lusc.Nursery,
      module_info_manager: ModuleInfoManager,
      build_handler: BuildHandler, open_document_registry: OpenDocumentRegistry,
      lsp_reader_writer: LspReaderWriter, diagnostics_helper: DiagnosticsHelper): DiagnosticsPublisher
end

function DiagnosticsPublisher:__init(
      root_nursery:lusc.Nursery, module_info_manager: ModuleInfoManager,
      build_handler: BuildHandler, open_document_registry: OpenDocumentRegistry,
      lsp_reader_writer: LspReaderWriter, diagnostics_helper: DiagnosticsHelper)
   self._root_nursery = root_nursery
   self._lsp_reader_writer = lsp_reader_writer
   self._diagnostics_helper = diagnostics_helper
   self._open_document_registry = open_document_registry
   self._change_detected = lusc.new_sticky_event()
   self._module_info_manager = module_info_manager
   self._build_handler = build_handler
end

function DiagnosticsPublisher:_build()
   local all_open_files = {}

   for file_path, _ in pairs(self._open_document_registry.docs) do
      local info = self._module_info_manager:try_get_or_create_module_info(file_path)
      if info ~= nil then
         table.insert(all_open_files, info)
      end
   end

   self._build_handler:build(all_open_files)

   for _, info in ipairs(all_open_files) do
      asserts.is_not_nil(info.uri)

      local diagnostics = self._diagnostics_helper:create_diagnostics(info)

      if #diagnostics > 0 then
         tracing.trace(_module_name, "Publishing {} diagnostics for {}: {@}", {#diagnostics, info.module_name, diagnostics})
      end

      tracing.trace(_module_name, "Publishing diagnostics for {}...", {info.uri.path})
      self._lsp_reader_writer:send_rpc_notification("textDocument/publishDiagnostics", {
         uri = Uri.tostring(info.uri),
         diagnostics = diagnostics,
         version = nil,
      } as lsp.Method.Params)
   end
end

function DiagnosticsPublisher:_build_open_files()
   local required_delay_without_saves_sec = 0.1

   while true do
      self._change_detected:await()
      self._change_detected:unset()

      -- it is common for many changes to occur at once, so delay
      -- slightly so we just perform one build
      while true do
         lusc.await_sleep(required_delay_without_saves_sec)
         if self._change_detected.is_set then
            tracing.debug(_module_name, "Detected consecutive change events, waiting again...", {})
            self._change_detected:unset()
         else
            tracing.trace(_module_name, "Successfully waited for buffer time. Now updating env...", {})
            break
         end
      end

      tracing.trace(_module_name, "Now updating env...", {})

      local start_time = uv.hrtime()

      self:_build()

      local elapsed_time_ms = (uv.hrtime() - start_time) / 1e6
      tracing.debug(_module_name, "Completed open documents build in {} ms", {elapsed_time_ms})
   end
end

function DiagnosticsPublisher:initialize()
   self._module_info_manager:observe_changes(function(_info: ModuleInfo, _old_dependencies: {string: boolean})
      self._change_detected:set()
   end)

   self._change_detected:set()

   self._root_nursery:start_soon(function()
      self:_build_open_files()
   end)
end

class.setup(DiagnosticsPublisher, "DiagnosticsPublisher", {
})

return DiagnosticsPublisher
