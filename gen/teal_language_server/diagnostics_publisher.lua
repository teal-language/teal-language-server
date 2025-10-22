local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; local _module_name = "diagnostics_publisher"


local BuildHandler = require("teal_language_server.build_handler")
local ModuleInfo = require("teal_language_server.module_info")
local class = require("teal_language_server.class")
local lusc = require("lusc")
local OpenDocumentRegistry = require("teal_language_server.open_document_registry")
local uv = require("luv")
local tracing = require("teal_language_server.tracing")
local asserts = require("teal_language_server.asserts")
local ModuleInfoManager = require("teal_language_server.module_info_manager")
local Uri = require("teal_language_server.uri")
local lsp = require("teal_language_server.lsp")
local LspReaderWriter = require("teal_language_server.lsp_reader_writer")
local DiagnosticsHelper = require("teal_language_server.diagnostics_helper")

local DiagnosticsPublisher = {}















function DiagnosticsPublisher:__init(
   root_nursery, module_info_manager,
   build_handler, open_document_registry,
   lsp_reader_writer, diagnostics_helper)
   self._root_nursery = root_nursery
   self._lsp_reader_writer = lsp_reader_writer
   self._diagnostics_helper = diagnostics_helper
   self._open_document_registry = open_document_registry
   self._change_detected = lusc.new_sticky_event()
   self._module_info_manager = module_info_manager
   self._build_handler = build_handler
end

function DiagnosticsPublisher:_build()
   self._build_handler:remove_deleted_modules()

   local all_open_files = {}

   for file_path, _ in pairs(self._open_document_registry.docs) do
      local info = self._module_info_manager:try_get_or_create_module_info(file_path)
      if info ~= nil then
         table.insert(all_open_files, info)
      end
   end

   local all_modules = self._build_handler:get_all_modules()
   self._build_handler:build(all_modules, all_open_files)

   for _, info in ipairs(all_open_files) do
      asserts.is_not_nil(info.uri)

      local diagnostics = self._diagnostics_helper:create_diagnostics(info)

      if #diagnostics > 0 then
         tracing.trace(_module_name, "Publishing {} diagnostics for {}: {@}", { #diagnostics, info.module_name, diagnostics })
      end

      tracing.trace(_module_name, "Publishing diagnostics for {}...", { info.uri.path })
      self._lsp_reader_writer:send_rpc_notification("textDocument/publishDiagnostics", {
         uri = Uri.tostring(info.uri),
         diagnostics = diagnostics,
         version = nil,
      })
   end
end

function DiagnosticsPublisher:_build_open_files()
   local required_delay_without_saves_sec = 0.1

   while true do
      self._change_detected:await()
      self._change_detected:unset()



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
      tracing.debug(_module_name, "Completed open documents build in {} ms", { elapsed_time_ms })
   end
end

function DiagnosticsPublisher:enqueue_build()
   self._change_detected:set()
end

function DiagnosticsPublisher:initialize()
   self._module_info_manager:observe_changes(function(_info, _old_dependencies)
      self._change_detected:set()
   end)

   self._change_detected:set()

   self._root_nursery:start_soon(function()
      self:_build_open_files()
   end)
end

class.setup(DiagnosticsPublisher, "DiagnosticsPublisher", {})


return DiagnosticsPublisher
