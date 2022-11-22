
local loop <const> = require("tealls.loop")
local lsp <const> = require("tealls.lsp")
local rpc <const> = require("tealls.rpc")
local handlers <const> = require("tealls.handlers")
local util <const> = require("tealls.util")

local args <const>: {string:string} = {}
-- very simple arg parsing
-- just match args that look like "foo=bar" and put them in a map
-- we don't need more than this since it will mostly be editor plugins using these anyway
for _, v in ipairs(arg) do
   local lhs <const>, rhs <const> = v:match("^([^=]-)=([^=]+)$")
   if lhs and rhs then
      args[lhs:lower()] = rhs:lower()
   end
end

local is_dev <const> = arg[0]:sub(-3, -1) == "dev"

util.set_logging(
   is_dev or args["logging"] == "on",
   args["logfile"] or
      (is_dev
         and "/tmp/teal-language-server-dev.log"
         or "/tmp/teal-language-server.log")
)
util.log("args: ", args)

local function assert_init()
   util.log("disabling buffering on stdin and stdout")
   util.assert(io.stdin:setvbuf("no"))
   util.assert(io.stdout:setvbuf("no"))

   util.log("waiting for initialize request")
   local data: {string:any}
   data = util.assert(rpc.decode())
   util.assert(data.method, "No method in initial request")
   util.assert(data.method == "initialize", "Initial method was not 'initialize'")
   handlers["initialize"](data.params as lsp.Method.Params, data.id as integer)
end

local running = true

local function input_job()
   while true do
      local data <const>, err = rpc.decode()
      if not data then
         util.log("Error: ", err)
         error(err)
      end

      if data.method then
         if data.method == "shutdown" then
            running = false
            break
         end
         loop.enqueue(function()
            local method <const> = data.method as lsp.Method.Name
            local params <const> = data.params as lsp.Method.Params
            util.log("Method: ", method)
            if handlers[method] then
               local ok: boolean
               ok, err = xpcall(function()
                  handlers[method](params, data.id as integer)
               end, debug.traceback as function) as (boolean, string)
               if not ok then
                  util.log("      error in handler for ", method, ": ", err)
               end
            else
               util.log("   ! no handler for ", method)
            end
         end)
         coroutine.yield()
      end
   end
end

local function start()
   util.log(("="):rep(30))
   util.log("starting...")
   assert_init()
   util.log("initialized!")

   loop.enqueue(input_job)
   while running do
      if not loop.step() then
         break
      end
   end

   util.log("shutting down...")
   util.log(("="):rep(30))
end

start()
