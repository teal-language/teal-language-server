local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local pcall = _tl_compat and _tl_compat.pcall or pcall; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall; local _module_name = "lsp.events_manager"

local lsp = require("teal_language_server.lsp.protocol")
local LspReaderWriter = require("teal_language_server.lsp.reader_writer")
local lusc = require("lusc")
local asserts = require("teal_language_server.util.asserts")
local logging = require("teal_language_server.logging")
local class = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local LspEventsManager = {}








function LspEventsManager:__init(root_nursery, lsp_reader_writer)
   asserts.is_not_nil(root_nursery)
   asserts.is_not_nil(lsp_reader_writer)

   self._handlers = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._root_nursery = root_nursery
end

function LspEventsManager:set_handler(method, handler)
   asserts.that(self._handlers[method] == nil)
   self._handlers[method] = handler
end

function LspEventsManager:_trigger(method, params, id)
   logger:info("Received request from client for method %s", method)

   if self._handlers[method] then
      local ok
      local err

      ok, err = xpcall(
      function() self._handlers[method](params, id) end,
      debug.traceback)

      if ok then
         logger:debug("Successfully handled request with method %s", method)
      else
         logger:error("Error in handler for request with method %s: %s", method, err)
      end
   else
      logger:warning("No handler found for event with method %s", method)
   end
end

function LspEventsManager:_receive_initialize_request()
   local initialize_data = self._lsp_reader_writer:receive_rpc()

   asserts.is_not_nil(initialize_data)

   asserts.that(initialize_data.method ~= nil, "No method in initial request")
   asserts.that(initialize_data.method == "initialize", "Initial method was not 'initialize'")

   logger:trace("Received initialize request from client with data: %s", initialize_data)

   self:_trigger(
   "initialize", initialize_data.params, initialize_data.id)
end

function LspEventsManager:initialize()
   self._root_nursery:start_soon(function()

      self:_receive_initialize_request()

      while true do
         local ok, data = pcall(self._lsp_reader_writer.receive_rpc, self._lsp_reader_writer)
         if not ok and lusc.is_cancelled_error(data) then


            error(data, 0)
         end
         if ok and data and data.method then
            self:_trigger(data.method, data.params, data.id)
         end
      end
   end)
end

class.setup(LspEventsManager, "LspEventsManager")
return LspEventsManager
