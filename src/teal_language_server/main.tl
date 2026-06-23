local _module_name = "main"

-- <imports>
local EnvUpdater <const> = require("teal_language_server.analysis.env_updater")
local DocumentManager <const> = require("teal_language_server.analysis.document_manager")
local ServerState <const> = require("teal_language_server.server_state")
local LspEventsManager <const> = require("teal_language_server.lsp.events_manager")
local lusc <const> = require("lusc")
local uv <const> = require("luv")
local args_parser <const> = require("teal_language_server.args_parser")
local MiscHandlers <const> = require("teal_language_server.handlers.misc_handlers")
local StdinReader <const> = require("teal_language_server.lsp.stdin_reader")
local LspReaderWriter <const> = require("teal_language_server.lsp.reader_writer")
local lsp <const> = require("teal_language_server.lsp.protocol")
local logging <const> = require("teal_language_server.logging")
local LogFileHandler = require("teal_language_server.log_file")
local util <const> = require("teal_language_server.util.util")

local logger = logging.get_logger(_module_name)

local record IDisposable
   dispose: function(IDisposable)
end

local function main()
   local args = args_parser.parse_args()

   local log_file: LogFileHandler.LogFile
   if args.log_mode ~= "none" then
      log_file = LogFileHandler.open_log_file(logging)
   end

   if args.verbose then
      logging.set_level("TRACE")
   elseif args.debug then
      logging.set_level(args.debug as logging.level)
   end


   if args.coverage then
      local ok, err = pcall(require, "luacov")
      if not ok then
         error("luacov is not installed. Install it manually with 'luarocks install luacov' or run 'luarocks test' to install test dependencies automatically.\n" .. tostring(err))
      end
   end

   logger:info("Started new instance teal-language-server. Lua Version: %s. Platform: %s", _VERSION, util.get_platform())
   logger:info("Received command line args: %s", args)
   logger:info("CWD = %s", uv.cwd())

   local disposables:{IDisposable}

   local function initialize()
      logger:debug("Running object graph construction phase...")

      local root_nursery = lusc.get_root_nursery()
      local stdin_reader = StdinReader()
      local lsp_reader_writer = LspReaderWriter(stdin_reader)
      local lsp_events_manager = LspEventsManager(root_nursery, lsp_reader_writer)
      local server_state = ServerState()
      local document_manager = DocumentManager(lsp_reader_writer, server_state)
      local env_updater = EnvUpdater(server_state, root_nursery, document_manager)
      local misc_handlers = MiscHandlers(lsp_events_manager, lsp_reader_writer, server_state, document_manager, args, log_file, env_updater)

      logger:debug("Running initialize phase...")
      stdin_reader:initialize()
      lsp_reader_writer:initialize()
      lsp_events_manager:initialize()
      misc_handlers:initialize()

      lsp_events_manager:set_handler("shutdown", function(_params:lsp.Method.Params, id:integer)
         logger:info("Received shutdown request from client.  Sending null response and cancelling all lusc tasks...")
         lsp_reader_writer:send_rpc(id, nil)
         root_nursery.cancel_scope:cancel()
      end)

      disposables =  {
         stdin_reader, lsp_reader_writer
      } as {IDisposable}
   end

   local function dispose()
      logger:info("Disposing...")

      if disposables then
         for _, disposable in ipairs(disposables) do
            disposable:dispose()
         end
      end

      if log_file then
         log_file:close()
      end
   end

   local lusc_timer = uv.new_timer()
   lusc_timer:start(0, 0, function()
      logger:trace("Received entry point call from luv")

      lusc.start {
         -- TODO - consider turning this off by default
         generate_debug_names = true,
         on_completed = function(err:lusc.ErrorGroup)
            if err ~= nil then
               logger:error("Received on_completed request with error:\n%s", err)
            else
               logger:info("Received on_completed request")
            end

            dispose()
         end,
      }

      lusc.schedule(function()
         logger:trace("Received entry point call from lusc luv")
         initialize()
      end)

      -- Tell lusc to end once all tasks complete
      lusc.stop()
   end)

   local function run_luv():nil
      logger:trace("Running luv event loop...")
      uv.run()
      logger:trace("Luv event loop stopped")
      lusc_timer:close()

      uv.walk(function(handle:uv.Handle)
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

   util.try {
      action = run_luv,
      catch = function(err:string):nil
         logger:error("Error: %s", err)
         error(err)
      end,
   }
end

main()

