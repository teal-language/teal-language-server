local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "server_state"


local asserts = require("tea_leaves.asserts")
local lsp = require("tea_leaves.lsp")
local Path = require("tea_leaves.path")
local lfs = require("lfs")
local TealProjectConfig = require("tea_leaves.teal_project_config")
local tl = require("tl")
local tracing = require("tea_leaves.tracing")
local class = require("tea_leaves.class")

local ServerState = {}














function ServerState:__init()
   self._has_initialized = false
end

local capabilities = {

   textDocumentSync = {
      openClose = true,
      change = lsp.sync_kind.Full,
      save = {
         includeText = true,
      },
   },
   hoverProvider = true,
   definitionProvider = true,

   completionProvider = {
      triggerCharacters = { ".", ":" },
   },
}

function ServerState:_validate_config(c)
   asserts.that(type(c) == "table", "Expected table, got {}", type(c))

   local function sort_in_place(t, fn)
      table.sort(t, fn)
      return t
   end

   local function from(fn, ...)
      local t = {}
      for val in fn, ... do
         table.insert(t, val)
      end
      return t
   end

   local function keys(t)
      local k
      return function()
         k = next(t, k)
         return k
      end
   end

   local function values(t)
      local k, v
      return function()
         k, v = next(t, k)
         return v
      end
   end

   local function get_types_in_array(val, typefn)
      typefn = typefn or type
      local set = {}
      for _, v in ipairs(val) do
         set[typefn(v)] = true
      end
      return sort_in_place(from(keys(set)))
   end

   local function get_array_type(val, default)
      if type(val) ~= "table" then
         return type(val)
      end
      local ts = get_types_in_array(val)
      if #ts == 0 then
         ts[1] = default
      end
      return "{" .. table.concat(ts, "|") .. "}"
   end

   local function get_map_type(val, default_key, default_value)
      if type(val) ~= "table" then
         return type(val)
      end

      local key_types = get_types_in_array(from(keys(val)))
      if #key_types == 0 then
         key_types[1] = default_key
      end


      local val_types = get_types_in_array(from(values(val)), get_array_type)
      if #val_types == 0 then
         val_types[1] = default_value
      end
      return "{" .. table.concat(key_types, "|") .. ":" .. table.concat(val_types, "|") .. "}"
   end

   local valid_keys = {
      build_dir = "string",
      source_dir = "string",
      module_name = "string",

      include = "{string}",
      exclude = "{string}",

      include_dir = "{string}",
      global_env_def = "string",
      scripts = "{string:{string}}",

      gen_compat = { ["off"] = true, ["optional"] = true, ["required"] = true },
      gen_target = { ["5.1"] = true, ["5.3"] = true },

      disable_warnings = "{string}",
      warning_error = "{string}",
   }

   local errs = {}
   local warnings = {}

   for k, v in pairs(c) do
      if k == "externals" then
         if type(v) ~= "table" then
            table.insert(errs, "Expected externals to be a table, got " .. type(v))
         end
      else
         local valid = valid_keys[k]
         if not valid then
            table.insert(warnings, string.format("Unknown key '%s'", k))
         elseif type(valid) == "table" then
            if not valid[v] then
               local sorted_keys = sort_in_place(from(keys(valid)))
               table.insert(errs, "Invalid value for " .. k .. ", expected one of: " .. table.concat(sorted_keys, ", "))
            end
         else
            local vtype = valid:find(":") and
            get_map_type(v, valid:match("^{(.*):(.*)}$")) or
            get_array_type(v, valid:match("^{(.*)}$"))

            if vtype ~= valid then
               table.insert(errs, string.format("Expected %s to be a %s, got %s", k, valid, vtype))
            end
         end
      end
   end

   local function verify_non_absolute_path(key)
      local val = (c)[key]
      if type(val) ~= "string" then

         return
      end
      local as_path = Path(val)
      if as_path:is_absolute() then
         table.insert(errs, string.format("Expected a non-absolute path for %s, got %s", key, as_path.value))
      end
   end
   verify_non_absolute_path("source_dir")
   verify_non_absolute_path("build_dir")

   local function verify_warnings(key)
      local arr = (c)[key]
      if arr then
         for _, warning in ipairs(arr) do
            if not tl.warning_kinds[warning] then
               table.insert(errs, string.format("Unknown warning in %s: %q", key, warning))
            end
         end
      end
   end
   verify_warnings("disable_warnings")
   verify_warnings("warning_error")

   asserts.that(#errs == 0, "Found {} errors and {} warnings in config:\n{}\n{}", #errs, #warnings, errs, warnings)

   if #warnings > 0 then
      tracing.warning(_module_name, "Found {} warnings in config:\n{}", { #warnings, warnings })
   end
end

function ServerState:_load_config(root_dir)
   local config_path = root_dir:join("tlconfig.lua")
   asserts.that(config_path:exists())

   local success, result = pcall(dofile, config_path.value)

   if success then
      local config = result
      self:_validate_config(config)
      return config
   end

   asserts.fail("Failed to parse tlconfig: {}", result)
end

function ServerState:set_env(env)
   asserts.is_not_nil(env)
   self._env = env
end

function ServerState:get_env()
   asserts.is_not_nil(self._env)
   return self._env
end

function ServerState:initialize(root_dir)
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   self._teal_project_root_dir = root_dir
   asserts.that(lfs.chdir(root_dir.value), "unable to chdir into {}", root_dir.value)

   self._config = self:_load_config(root_dir)
end

class.setup(ServerState, "ServerState", {
   getters = {
      capabilities = function()
         return capabilities
      end,
      name = function()
         return "tea-leaves"
      end,
      version = function()
         return "0.0.1"
      end,
      teal_project_root_dir = function(self)
         return self._teal_project_root_dir
      end,
      config = function(self)
         return self._config
      end,
   },
   nilable_members = {
      '_teal_project_root_dir', '_config', '_env',
   },
})

return ServerState
