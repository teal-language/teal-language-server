local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "env_updater"


local DocumentManager = require("teal_language_server.analysis.document_manager")
local lua_env = require("teal_language_server.analysis.lua_env")
local lusc = require("lusc")
local ServerState = require("teal_language_server.server_state")
local tl = require("teal_language_server.tl")
local uv = require("luv")
local asserts = require("teal_language_server.util.asserts")
local tracing = require("teal_language_server.logging.tracing")
local class = require("teal_language_server.util.class")

local init_path = package.path
local init_cpath = package.cpath

local function dedup_path(path_str)
   local seen = {}
   local result = {}


   for entry in path_str:gmatch("[^;]+") do
      if not seen[entry] then
         seen[entry] = true
         table.insert(result, entry)
      end
   end
   return table.concat(result, ";")
end

local EnvUpdater = {}








function EnvUpdater:__init(server_state, root_nursery, document_manager)
   asserts.is_not_nil(document_manager)

   self._change_detected = lusc.new_sticky_event()
   self._server_state = server_state
   self._root_nursery = root_nursery
   self._document_manager = document_manager
end

function EnvUpdater:_init_env_from_config(cfg)
   local function ivalues(t)
      local i = 0
      return function()
         i = i + 1
         return t[i]
      end
   end

   local path_separator = package.config:sub(1, 1)
   local shared_lib_ext = package.cpath:match("(%.%w+)%s*$") or ".so"

   local function prepend_to_lua_path(path_str)
      if path_str:sub(-1) == path_separator then
         path_str = path_str:sub(1, -2)
      end

      path_str = path_str .. path_separator

      package.path = path_str .. "?.lua;" ..
      path_str .. "?" .. path_separator .. "init.lua;" ..
      package.path

      package.cpath = path_str .. "?." .. shared_lib_ext .. ";" ..
      package.cpath
   end

   local function init_teal_env(gen_compat, gen_target, env_def)
      local opts = {
         defaults = {
            gen_compat = gen_compat,
            gen_target = gen_target,
         },
         predefined_modules = { env_def },
      }

      local env = tl.new_env(opts)
      env.report_types = true

      tl.check_string("", env, "bootstrap.tl")
      return env
   end

   cfg = cfg or {}

   for dir in ivalues(cfg.include_dir or {}) do
      prepend_to_lua_path(dir)
   end

   if cfg.source_dir then
      prepend_to_lua_path(cfg.source_dir)
   end

   tracing.debug(_module_name, "Final package.path: {}", { package.path })
   tracing.debug(_module_name, "Final package.cpath: {}", { package.cpath })

   local env, err = init_teal_env(cfg.gen_compat, cfg.gen_target, cfg.global_env_def)
   if not env then
      return nil, err
   end

   return env
end

function EnvUpdater:_generate_env()
   local config = self._server_state.config
   asserts.is_not_nil(config)



   package.path = init_path
   package.cpath = init_cpath

   local env, errs = self:_init_env_from_config(config)

   if errs ~= nil and #errs > 0 then
      tracing.debug(_module_name, "Loaded env with errors:\n{}", { errs })
   end

   return env
end

function EnvUpdater:_update_env_on_changes()
   local required_delay_without_saves_sec = 0.1

   while true do
      self._change_detected:await()
      self._change_detected:unset()




      while true do
         lusc.await_sleep(required_delay_without_saves_sec)
         if self._change_detected.is_set then
            tracing.debug(_module_name, "Detected consecutive change events, waiting again...", {})
            self._change_detected:unset()
         else
            tracing.debug(_module_name, "Successfully waited for buffer time. Now updating env...", {})
            break
         end
      end

      tracing.debug(_module_name, "Now updating env...", {})
      local start_time = uv.hrtime()
      local env = self:_generate_env()
      self._server_state:set_env(env)
      local elapsed_time_ms = (uv.hrtime() - start_time) / 1e6
      tracing.debug(_module_name, "Completed env update in {} ms", { elapsed_time_ms })

      for _, doc in pairs(self._document_manager.docs) do
         doc:clear_cache()
         doc:process_and_publish_results()
      end
   end
end

function EnvUpdater:schedule_env_update()
   self._change_detected:set()
end

function EnvUpdater:initialize()
   local root = self._server_state.teal_project_root_dir.value
   local lua_bin = lua_env.find_lua_bin(root)
   tracing.info(_module_name, "Using lua binary for env discovery: {}", { lua_bin })
   local discovered_user_path, discovered_user_cpath = lua_env.discover_paths(lua_bin)
   if discovered_user_path then
      init_path = dedup_path(init_path .. ";" .. discovered_user_path)
      tracing.info(_module_name, "Discovered user lua path: {}", { discovered_user_path })
   end

   if discovered_user_cpath then
      init_cpath = dedup_path(init_cpath .. ";" .. discovered_user_cpath)
      tracing.info(_module_name, "Discovered user lua cpath: {}", { discovered_user_cpath })
   end

   local env = self:_generate_env()
   self._server_state:set_env(env)

   self._root_nursery:start_soon(function()
      self:_update_env_on_changes()
   end)
end

class.setup(EnvUpdater, "EnvUpdater")
return EnvUpdater
