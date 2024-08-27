local _module_name = "server_state"

-- <imports>
local asserts <const> = require("tea_leaves.asserts")
local lsp <const> = require("tea_leaves.lsp")
local Path <const> = require("tea_leaves.path")
local lfs <const> = require("lfs")
local TealProjectConfig = require("tea_leaves.teal_project_config")
local tl <const> = require("tl")
local tracing <const> = require("tea_leaves.tracing")
local class <const> = require("tea_leaves.class")

local record ServerState
   capabilities:{string:any}
   name: string
   version: string
   config: TealProjectConfig
   teal_project_root_dir: Path

   _has_initialized: boolean
   _teal_project_root_dir: Path
   _config: TealProjectConfig
   _env: tl.Env

   metamethod __call: function(self: ServerState): ServerState
end

function ServerState:__init()
   self._has_initialized = false
end

local capabilities = {
   -- we basically do the bare minimum
   textDocumentSync = {
      openClose = true,
      change = lsp.sync_kind.Full,
      save = {
         includeText = true,
      },
   },
   hoverProvider = true,
   definitionProvider = true,
   -- typeDefinitionProvider = true,
   completionProvider = {
      triggerCharacters = { ".", ":" },
   },
}

function ServerState:_validate_config(c:TealProjectConfig)
   asserts.that(type(c) == "table", "Expected table, got {}", type(c))

   local function sort_in_place<Value>(t: {Value}, fn: function(Value, Value): boolean): {Value}
      table.sort(t, fn)
      return t
   end

   local function from<Value>(fn: function(...: any): (Value), ...: any): {Value}
      local t = {}
      for val in fn, ... do
         table.insert(t, val)
      end
      return t
   end

   local function keys<Key>(t: {Key:any}): function(): Key
      local k: Key
      return function(): Key
         k = next(t, k)
         return k
      end
   end

   local function values<Key, Value>(t: {Key:Value}): function(): Value
      local k, v: Key, Value
      return function(): Value
         k, v = next(t, k)
         return v
      end
   end

   local function get_types_in_array(val: {any}, typefn: function(any): string): {string}
      typefn = typefn or type
      local set <const> = {}
      for _, v in ipairs(val) do
         set[typefn(v)] = true
      end
      return sort_in_place(from(keys(set)))
   end

   local function get_array_type(val: any, default: string): string
      if type(val) ~= "table" then
         return type(val)
      end
      local ts <const> = get_types_in_array(val as {any})
      if #ts == 0 then
         ts[1] = default
      end
      return "{" .. table.concat(ts, "|") .. "}"
   end

   local function get_map_type(val: any, default_key: string, default_value: string): string
      if type(val) ~= "table" then
         return type(val)
      end

      local key_types <const> = get_types_in_array(from(keys(val as {any:any})))
      if #key_types == 0 then
         key_types[1] = default_key
      end

      -- bias values towards array types, since we probably won't use nested maps
      local val_types <const> = get_types_in_array(from(values(val as {any:any})), get_array_type as function(any): string)
      if #val_types == 0 then
         val_types[1] = default_value
      end
      return "{" .. table.concat(key_types, "|") .. ":" .. table.concat(val_types, "|") .. "}"
   end

   local valid_keys <const>: {string:string|{string:boolean}} = {
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

   local errs <const>: {string} = {}
   local warnings <const>: {string} = {}

   for k, v in pairs(c as {string:any}) do
      if k == "externals" then
         if type(v) ~= "table" then
            table.insert(errs, "Expected externals to be a table, got " .. type(v))
         end
      else
         local valid <const> = valid_keys[k]
         if not valid then
            table.insert(warnings, string.format("Unknown key '%s'", k))
         elseif valid is {string:boolean} then
            if not valid[v as string] then
               local sorted_keys = sort_in_place(from(keys(valid)))
               table.insert(errs, "Invalid value for " .. k .. ", expected one of: " .. table.concat(sorted_keys, ", "))
            end
         else
            local vtype <const> = valid:find(":")
               and get_map_type(v, valid:match("^{(.*):(.*)}$"))
               or get_array_type(v, valid:match("^{(.*)}$"))

            if vtype ~= valid then
               table.insert(errs, string.format("Expected %s to be a %s, got %s", k, valid, vtype))
            end
         end
      end
   end

   local function verify_non_absolute_path(key: string)
      local val = (c as {string:string})[key]
      if type(val) ~= "string" then
         -- error already generated an error or wasn't provided
         return
      end
      local as_path = Path(val)
      if as_path:is_absolute() then
         table.insert(errs, string.format("Expected a non-absolute path for %s, got %s", key, as_path.value))
      end
   end
   verify_non_absolute_path("source_dir")
   verify_non_absolute_path("build_dir")

   local function verify_warnings(key: string)
      local arr <const> = (c as {string:{string}})[key]
      if arr then
         for _, warning in ipairs(arr) do
            if not tl.warning_kinds[warning as tl.WarningKind] then
               table.insert(errs, string.format("Unknown warning in %s: %q", key, warning))
            end
         end
      end
   end
   verify_warnings("disable_warnings")
   verify_warnings("warning_error")

   asserts.that(#errs == 0, "Found {} errors and {} warnings in config:\n{}\n{}", #errs, #warnings, errs, warnings)

   if #warnings > 0 then
      tracing.warning(_module_name, "Found {} warnings in config:\n{}", {#warnings, warnings})
   end
end

function ServerState:_load_config(root_dir:Path):TealProjectConfig
   local config_path = root_dir:join("tlconfig.lua")
   asserts.that(config_path:exists())

   local success, result = pcall(dofile, config_path.value)

   if success then
      local config = result as TealProjectConfig
      self:_validate_config(config)
      return config
   end

   asserts.fail("Failed to parse tlconfig: {}", result)
end

function ServerState:set_env(env:tl.Env)
   asserts.is_not_nil(env)
   self._env = env
end

function ServerState:get_env(): tl.Env
   asserts.is_not_nil(self._env)
   return self._env
end

function ServerState:initialize(root_dir:Path)
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   self._teal_project_root_dir = root_dir
   asserts.that(lfs.chdir(root_dir.value), "unable to chdir into {}", root_dir.value)

   self._config = self:_load_config(root_dir)
end

class.setup(ServerState, "ServerState", {
   getters = {
      capabilities = function():{string:any}
         return capabilities
      end,
      name = function():string
         return "tea-leaves"
      end,
      version = function():string
         return "0.0.1"
      end,
      teal_project_root_dir = function(self:ServerState):Path
         return self._teal_project_root_dir
      end,
      config = function(self:ServerState):TealProjectConfig
         return self._config
      end,
   },
   nilable_members = {
      '_teal_project_root_dir', '_config', '_env'
   }
})

return ServerState
