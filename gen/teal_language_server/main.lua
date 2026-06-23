local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local _module_name = "main"


local EnvUpdater = require("teal_language_server.analysis.env_updater")
local DocumentManager = require("teal_language_server.analysis.document_manager")
local ServerState = require("teal_language_server.server_state")
local LspEventsManager = require("teal_language_server.lsp.events_manager")
local lusc = require("lusc")
local uv = require("luv")
local args_parser = require("teal_language_server.args_parser")
local MiscHandlers = require("teal_language_server.handlers.misc_handlers")
local StdinReader = require("teal_language_server.lsp.stdin_reader")
local LspReaderWriter = require("teal_language_server.lsp.reader_writer")
local lsp = require("teal_language_server.lsp.protocol")
local logging = require("teal_language_server.logging")
local util = require("teal_language_server.util.util")

local logger = logging.get_logger(_module_name)





local function main()
   local args = args_parser.parse_args()

   if args.coverage then
      local ok, err = pcall(require, "luacov")
      if not ok then
         error("luacov is not installed. Install it manually with 'luarocks install luacov' or run 'luarocks test' to install test dependencies automatically.\n" .. tostring(err))
      end
   end

   logger:info("Started new instance teal-language-server. Lua Version: %s. Platform: %s", _VERSION, util.get_platform())
   logger:info("Received command line args: %s", args)
   logger:info("CWD = %s", uv.cwd())

   local disposables

   local function initialize()
      logger:debug("Running object graph construction phase...")

      local root_nursery = lusc.get_root_nursery()
      local stdin_reader = StdinReader()
      local lsp_reader_writer = LspReaderWriter(stdin_reader)
      local lsp_events_manager = LspEventsManager(root_nursery, lsp_reader_writer)
      local server_state = ServerState()
      local document_manager = DocumentManager(lsp_reader_writer, server_state)
      local env_updater = EnvUpdater(server_state, root_nursery, document_manager)
      local misc_handlers = MiscHandlers(lsp_events_manager, lsp_reader_writer, server_state, document_manager, args, env_updater)

      logger:debug("Running initialize phase...")
      stdin_reader:initialize()
      lsp_reader_writer:initialize()
      lsp_events_manager:initialize()
      misc_handlers:initialize()

      lsp_events_manager:set_handler("shutdown", function(_params, id)
         logger:info("Received shutdown request from client.  Sending null response and cancelling all lusc tasks...")
         lsp_reader_writer:send_rpc(id, nil)
         root_nursery.cancel_scope:cancel()
      end)

      disposables = {
         stdin_reader, lsp_reader_writer,
      }
   end

   local function dispose()
      logger:info("Disposing...")

      if disposables then
         for _, disposable in ipairs(disposables) do
            disposable:dispose()
         end
      end
   end

   local lusc_timer = uv.new_timer()
   lusc_timer:start(0, 0, function()
      logger:trace("Received entry point call from luv")

      lusc.start({

         generate_debug_names = true,
         on_completed = function(err)
            if err ~= nil then
               logger:error("Received on_completed request with error:\n%s", err)
            else
               logger:info("Received on_completed request")
            end

            dispose()
         end,
      })

      lusc.schedule(function()
         logger:trace("Received entry point call from lusc luv")
         initialize()
      end)


      lusc.stop()
   end)

   local function run_luv()
      logger:trace("Running luv event loop...")
      uv.run()
      logger:trace("Luv event loop stopped")
      lusc_timer:close()

      uv.walk(function(handle)
         if not handle:is_closing() then
            local handle_type = handle:get_type()
            logger:warning("Found unclosed handle of type '%s', closing it.", handle_type)
            handle:close()
         end
      end)

      uv.run('nowait')

      if uv.loop_close() then
         logger:info("luv event loop closed gracefully")
      else
         logger:warning("Could not close luv event loop gracefully")
      end
   end

   util.try({
      action = run_luv,
      catch = function(err)
         logger:error("Error: %s", err)
         error(err)
      end,
   })
end

main()
