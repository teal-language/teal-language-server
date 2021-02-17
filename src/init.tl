
local lsp <const> = require("tealls.lsp")
local rpc <const> = require("tealls.rpc")
local handlers <const> = require("tealls.handlers")
local util <const> = require("tealls.util")

local args <const>: {string:string} = {}
-- very simple arg parsing
-- just match args that look like "foo=bar" and put them in a map
for _, v in ipairs{...} do
   local lhs <const>, rhs <const> = v:match("^[^=]+=[^=]+$")
   if lhs and rhs then
      args[lhs:lower()] = rhs:lower()
   end
end

-- util.set_logging(args["logging"] == "on")
util.set_logging(true)
util.log("args: ", args)

local function assert_init()
   util.log("waiting for initialize request")
   local data = util.assert(rpc.decode())
   util.assert(data.method, "No method in initial request")
   util.assert(data.method == "initialize", "Initial method was not 'initialize'")
   handlers["initialize"](data.params as lsp.Method.Params, data.id as number)
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
         local method <const> = data.method as lsp.Method.Name
         local params <const> = data.params as lsp.Method.Params
         util.log("Method: ", method)
         if handlers[method] then
            util.log("   dispatching handler...")
            local ok: boolean
            ok, err = xpcall(function()
               handlers[method](params, data.id as number)
            end, debug.traceback as function) as (boolean, string)
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

