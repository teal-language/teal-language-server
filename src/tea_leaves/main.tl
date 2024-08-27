local _module_name = "main"

-- <imports>
local EnvUpdater <const> = require("tea_leaves.env_updater")
local DocumentManager <const> = require("tea_leaves.document_manager")
local ServerState <const> = require("tea_leaves.server_state")
local LspEventsManager <const> = require("tea_leaves.lsp_events_manager")
local lusc <const> = require("lusc")
local uv <const> = require("luv")
local TraceStream <const> = require("tea_leaves.trace_stream")
local args_parser <const> = require("tea_leaves.args_parser")
local MiscHandlers <const> = require("tea_leaves.misc_handlers")
local StdinReader <const> = require("tea_leaves.stdin_reader")
local LspReaderWriter <const> = require("tea_leaves.lsp_reader_writer")
local tracing <const> = require("tea_leaves.tracing")
local util <const> = require("tea_leaves.util")
local TraceEntry <const> = require("tea_leaves.trace_entry")

local record IDisposable
   dispose: function(IDisposable)
end

local function init_logging(verbose:boolean):TraceStream
   local trace_stream = TraceStream()
   trace_stream:initialize()

   tracing.add_stream(function(entry:TraceEntry)
      trace_stream:log_entry(entry)
   end)

   if verbose then
      tracing.set_min_level("TRACE")
   else
      tracing.set_min_level("INFO")
   end
   return trace_stream
end

local function main()
   -- Immediately listen to log events and cache until
   -- we set up our file logger
   local cached_entries:{TraceEntry} = {}
   tracing.add_stream(function(entry:TraceEntry)
      if cached_entries then
         table.insert(cached_entries, entry)
      end
   end)

   local args = args_parser.parse_args()

   local trace_stream:TraceStream

   if args.log_mode ~= "none" then
      trace_stream = init_logging(args.verbose)

      for _, entry in ipairs(cached_entries) do
         trace_stream:log_entry(entry)
      end

      -- Uncomment if lusc is suspected to have an issue
      -- lusc.set_log_handler(function(message:string)
      --    tracing.debug("lusc", message, {})
      -- end)
   end

   cached_entries = nil

   tracing.info(_module_name, "Started new instance tea-leaves. Lua Version: {version}. Platform: {platform}", {_VERSION, util.get_platform()})
   tracing.info(_module_name, "Received command line args: {}", {args})
   tracing.info(_module_name, "CWD = {cwd}", {uv.cwd()})

   local disposables:{IDisposable}

   local function initialize()
      tracing.debug(_module_name, "Running object graph construction phase...", {})

      local root_nursery = lusc.get_root_nursery()
      local stdin_reader = StdinReader()
      local lsp_reader_writer = LspReaderWriter(stdin_reader)
      local lsp_events_manager = LspEventsManager(root_nursery, lsp_reader_writer)
      local server_state = ServerState()
      local document_manager = DocumentManager(lsp_reader_writer, server_state)
      local env_updater = EnvUpdater(server_state, root_nursery, document_manager)
      local misc_handlers = MiscHandlers(lsp_events_manager, lsp_reader_writer, server_state, document_manager, trace_stream, args, env_updater)

      tracing.debug(_module_name, "Running initialize phase...", {})
      stdin_reader:initialize()
      lsp_reader_writer:initialize()
      lsp_events_manager:initialize()
      misc_handlers:initialize()

      lsp_events_manager:set_handler("shutdown", function()
         tracing.info(_module_name, "Received shutdown request from client.  Cancelling all lusc tasks...", {})
         root_nursery.cancel_scope:cancel()
      end)

      disposables =  {
         stdin_reader, lsp_reader_writer
      } as {IDisposable}
   end

   local function dispose()
      tracing.info(_module_name, "Disposing...", {})

      if disposables then
         for _, disposable in ipairs(disposables) do
            disposable:dispose()
         end
      end
   end

   local lusc_timer = uv.new_timer()
   lusc_timer:start(0, 0, function()
      tracing.trace(_module_name, "Received entry point call from luv")

      lusc.start {
         -- TODO - consider turning this off by default
         generate_debug_names = true,
         on_completed = function(err:lusc.ErrorGroup)
            if err ~= nil then
               tracing.error(_module_name, "Received on_completed request with error:\n{error}", {err})
            else
               tracing.info(_module_name, "Received on_completed request")
            end

            dispose()
         end,
      }

      lusc.schedule(function()
         tracing.trace(_module_name, "Received entry point call from lusc luv")
         initialize()
      end)

      -- Tell lusc to end once all tasks complete
      lusc.stop()
   end)

   local function run_luv():nil
      tracing.trace(_module_name, "Running luv event loop...")
      uv.run()
      tracing.trace(_module_name, "Luv event loop stopped")
      lusc_timer:close()

      uv.walk(function(handle:uv.Handle)
         if not handle:is_closing() then
            local handle_type = handle:get_type()
            tracing.warning(_module_name, "Found unclosed handle of type '{handle_type}', closing it.", {handle_type})
            handle:close()
         end
      end)

      uv.run('nowait')

      if uv.loop_close() then
         tracing.info(_module_name, "luv event loop closed gracefully")
      else
         tracing.warning(_module_name, "Could not close luv event loop gracefully")
      end
   end

   util.try {
      action = run_luv,
      catch = function(err:string):nil
         tracing.error(_module_name, "Error: {error}", {err})
         error(err)
      end,
   }
end

main()

