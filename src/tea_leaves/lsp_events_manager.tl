local _module_name = "lsp_events_manager"

local lsp <const> = require("tea_leaves.lsp")
local LspReaderWriter <const> = require("tea_leaves.lsp_reader_writer")
local lusc <const> = require("lusc")
local asserts <const> = require("tea_leaves.asserts")
local tracing <const> = require("tea_leaves.tracing")
local class <const> = require("tea_leaves.class")

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
   tracing.info(_module_name, "Received request from client for method {}", {method})

   if self._handlers[method] then
      local ok: boolean
      local err: string

      ok, err = xpcall(
         function() self._handlers[method](params, id) end,
         debug.traceback as function) as (boolean, string)

      if ok then
         tracing.debug(_module_name, "Successfully handled request with method {}", {method})
      else
         tracing.error(_module_name, "Error in handler for request with method {}: {}", {method, err})
      end
   else
      tracing.warning(_module_name, "No handler found for event with method {}", {method})
   end
end

function LspEventsManager:_receive_initialize_request()
   local initialize_data = self._lsp_reader_writer:receive_rpc()

   asserts.is_not_nil(initialize_data)

   asserts.that(initialize_data.method ~= nil, "No method in initial request")
   asserts.that(initialize_data.method == "initialize", "Initial method was not 'initialize'")

   tracing.trace(_module_name, "Received initialize request from client with data: {}", {initialize_data})

   self:_trigger(
      "initialize", initialize_data.params as lsp.Method.Params, initialize_data.id as integer)
end

function LspEventsManager:initialize()
   self._root_nursery:start_soon(function()
      -- Initialize method must be first
      self:_receive_initialize_request()

      while true do
         local data = self._lsp_reader_writer:receive_rpc()
         asserts.is_not_nil(data)
         asserts.is_not_nil(data.method)

         self:_trigger(
            data.method as lsp.Method.Name, data.params as lsp.Method.Params, data.id as integer)
      end
   end)
end

class.setup(LspEventsManager, "LspEventsManager")
return LspEventsManager
