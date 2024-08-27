local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local package = _tl_compat and _tl_compat.package or package; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local _module_name = "env_updater"


local DocumentManager = require("tea_leaves.document_manager")
local lusc = require("lusc")
local ServerState = require("tea_leaves.server_state")
local tl = require("tl")
local TealProjectConfig = require("tea_leaves.teal_project_config")
local uv = require("luv")
local asserts = require("tea_leaves.asserts")
local tracing = require("tea_leaves.tracing")
local class = require("tea_leaves.class")

local init_path = package.path
local init_cpath = package.cpath

local EnvUpdater = {}









function EnvUpdater:__init(server_state, root_nursery, document_manager)
   asserts.is_not_nil(document_manager)

   self._change_detected = lusc.new_sticky_event()
   self._server_state = server_state
   self._substitutions = {}
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

   local function esc_char(c)
      return "%" .. c
   end

   local function str_esc(s, sub)
      return s:gsub(
      "[%^%$%(%)%%%.%[%]%*%+%-%?]",
      sub or
      esc_char)

   end

   local function add_module_substitute(source_dir, mod_name)
      self._substitutions[source_dir] = "^" .. str_esc(mod_name)
   end

   local function init_teal_env(gen_compat, gen_target, env_def)
      return tl.init_env(false, gen_compat, gen_target, { env_def })
   end

   cfg = cfg or {}

   for dir in ivalues(cfg.include_dir or {}) do
      prepend_to_lua_path(dir)
   end

   if cfg.source_dir and cfg.module_name then
      add_module_substitute(cfg.source_dir, cfg.module_name)
   end

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
   local env = self:_generate_env()
   self._server_state:set_env(env)

   self._root_nursery:start_soon(function()
      self:_update_env_on_changes()
   end)
end

class.setup(EnvUpdater, "EnvUpdater")
return EnvUpdater
