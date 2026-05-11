local _module_name = "env_factory"
local tl <const> = require("tl")
local ServerState <const> = require("teal_language_server.server_state")
local asserts <const> = require("teal_language_server.asserts")
local class <const> = require("teal_language_server.class")
local tracing <const> = require("teal_language_server.tracing")

-- <imports>

local record EnvFactory
   _server_state: ServerState
   _has_initialized: boolean

   metamethod __call: function(self: EnvFactory, server_state: ServerState): EnvFactory
end

function EnvFactory:__init(server_state: ServerState)
   self._server_state = server_state
   self._has_initialized = false
end

function EnvFactory:initialize()
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   local path_separator = package.config:sub(1, 1)
   local shared_lib_ext = package.cpath:match("(%.%w+)%s*$") or ".so"

   for _, path_str in ipairs(self._server_state.source_dirs) do
      -- We assume path is canonicalized, so no trailing slash
      path_str = path_str .. path_separator

      package.path = path_str .. "?.lua;"
         .. path_str .. "?" .. path_separator .. "init.lua;"
         .. package.path

      package.cpath = path_str .. "?." .. shared_lib_ext .. ";"
         .. package.cpath
   end
end

function EnvFactory:generate_env(): tl.Env
   asserts.that(self._has_initialized)

   local config = self._server_state.config
   asserts.is_not_nil(config)

   local defaults:tl.CheckOptions =  {
      gen_compat = config.gen_compat,
      gen_target = config.gen_target,
      feat_arity = "on",
   }
   tracing.debug(_module_name, "Using env defaults: {@}", {defaults})

   local opts:tl.EnvOptions = {
      defaults = defaults,
      predefined_modules = {config.global_env_def},
   }

   local env, err_str = tl.new_env(opts)
   asserts.that(env ~= nil, "Failed to initialize env: {}", err_str)
   env.report_types = true
   return env
end

class.setup(EnvFactory, "EnvFactory")
return EnvFactory
