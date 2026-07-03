local _module_name = "lsp.events_manager"

local lsp <const> = require("teal_language_server.lsp.protocol")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local lusc <const> = require("lusc")
local asserts <const> = require("teal_language_server.util.asserts")
local logging <const> = require("teal_language_server.logging")
local class <const> = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local record LspEventsManager
   _lsp_reader_writer: LspReaderWriter
   _root_nursery:lusc.Nursery

   _handlers:{lsp.Method.Name: function(lsp.Method.Params, integer)}

   metamethod __call: function(self: LspEventsManager, root_nursery:lusc.Nursery, lsp_reader_writer:LspReaderWriter): LspEventsManager
end

function LspEventsManager:__init(root_nursery:lusc.Nursery, lsp_reader_writer:LspReaderWriter)
   asserts.is_not_nil(root_nursery)
   asserts.is_not_nil(lsp_reader_writer)

   self._handlers = {}
   self._lsp_reader_writer = lsp_reader_writer
   self._root_nursery = root_nursery
end

function LspEventsManager:set_handler(method:lsp.Method.Name, handler:function(lsp.Method.Params, integer))
   asserts.that(self._handlers[method] == nil)
   self._handlers[method] = handler
end

function LspEventsManager:_trigger(method:lsp.Method.Name, params:lsp.Method.Params, id:integer)
   logger:info("Received request from client for method %s", method)

   if self._handlers[method] then
      local ok: boolean
      local err: string

      ok, err = xpcall(
         function() self._handlers[method](params, id) end,
         debug.traceback as function) as (boolean, string)

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
      "initialize", initialize_data.params as lsp.Method.Params, initialize_data.id as integer)
end

function LspEventsManager:initialize()
   self._root_nursery:start_soon(function()
      -- Initialize method must be first
      self:_receive_initialize_request()

      while true do
         -- Must go through xpcall (not pcall): receive_rpc yields while awaiting
         -- stdin data, and on Lua 5.1 only xpcall is patched (see bin/teal-language-server)
         -- to allow yielding across this C-call boundary. A plain pcall here breaks
         -- the read loop on every iteration under Lua 5.1, so the server never
         -- processes another message after `initialize`.
         local ok, data = xpcall(
            function(): {string:any} return self._lsp_reader_writer:receive_rpc() end,
            debug.traceback as function) as (boolean, {string:any})
         if not ok and lusc.is_cancelled_error(data) then
            -- Let shutdown's nursery cancellation actually unwind this task,
            -- instead of catching it here and retrying forever.
            error(data, 0)
         end
         if ok and data and data.method then
            self:_trigger(data.method as lsp.Method.Name, data.params as lsp.Method.Params, data.id as integer)
         end
      end
   end)
end

class.setup(LspEventsManager, "LspEventsManager")
return LspEventsManager
