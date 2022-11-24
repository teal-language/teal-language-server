local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
local lsp = require("tealls.lsp")
local rpc = require("tealls.rpc")
local handlers = require("tealls.handlers")
local util = require("tealls.util")

local args = {}



for _, v in ipairs(arg) do
   local lhs, rhs = v:match("^([^=]-)=([^=]+)$")
   if lhs and rhs then
      args[lhs:lower()] = rhs:lower()
   end
end


util.log("args: ", args)

local function assert_init()
   util.log("waiting for initialize request")
   local data = util.assert(rpc.decode())
   util.assert(data.method, "No method in initial request")
   util.assert(data.method == "initialize", "Initial method was not 'initialize'")
   handlers["initialize"](data.params, data.id)
end

local function start()
   util.log(("="):rep(30))
   util.log("starting...")
   assert_init()
   util.log("initialized!")

   while true do
      local data, err = rpc.decode()
      if not data then
         util.log("Error: ", err)
         error(err)
      end

      if data.method then
         if data.method == "shutdown" then
            break
         end
         local method = data.method
         local params = data.params
         util.log("Method: ", method)
         if handlers[method] then
            local ok
            ok, err = xpcall(function()
               handlers[method](params, data.id)
            end, debug.traceback)
            if not ok then
               util.log("      error in handler for ", method, ": ", err)
            end
         else
            util.log("   ! no handler for ", method)
         end
      end
   end

   util.log("shutting down...")
   util.log(("="):rep(30))
end

start()