local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local package = _tl_compat and _tl_compat.package or package; local string = _tl_compat and _tl_compat.string or string; local _module_name = "env_factory"
local tl = require("tl")
local ServerState = require("teal_language_server.server_state")
local asserts = require("teal_language_server.asserts")
local class = require("teal_language_server.class")
local tracing = require("teal_language_server.tracing")



local EnvFactory = {}






function EnvFactory:__init(server_state)
   self._server_state = server_state
   self._has_initialized = false
end

function EnvFactory:initialize()
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   local path_separator = package.config:sub(1, 1)
   local shared_lib_ext = package.cpath:match("(%.%w+)%s*$") or ".so"

   for _, path_str in ipairs(self._server_state.source_dirs) do

      path_str = path_str .. path_separator

      package.path = path_str .. "?.lua;" ..
      path_str .. "?" .. path_separator .. "init.lua;" ..
      package.path

      package.cpath = path_str .. "?." .. shared_lib_ext .. ";" ..
      package.cpath
   end
end

function EnvFactory:generate_env()
   asserts.that(self._has_initialized)

   local config = self._server_state.config
   asserts.is_not_nil(config)

   local defaults = {
      gen_compat = config.gen_compat,
      gen_target = config.gen_target,
      feat_arity = "on",
   }
   tracing.debug(_module_name, "Using env defaults: {@}", { defaults })

   local opts = {
      defaults = defaults,
      predefined_modules = { config.global_env_def },
   }

   local env, err_str = tl.new_env(opts)
   asserts.that(env ~= nil, "Failed to initialize env: {}", err_str)
   env.report_types = true
   return env
end

class.setup(EnvFactory, "EnvFactory")
return EnvFactory
