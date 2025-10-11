local _module_name = "build_handler"

-- <imports>
local tracing <const> = require("teal_language_server.tracing")
local ModuleInfo <const> = require("teal_language_server.module_info")
local asserts <const> = require("teal_language_server.asserts")
local ServerState <const> = require("teal_language_server.server_state")
local class <const> = require("teal_language_server.class")
local EnvFactory <const> = require("teal_language_server.env_factory")
local tl <const> = require("tl")
local ModuleInfoManager <const> = require("teal_language_server.module_info_manager")
local OpenDocumentRegistry <const> = require("teal_language_server.open_document_registry")
local files_util <const> = require("teal_language_server.files_util")
local path_util <const> = require("teal_language_server.path_util")

local record BuildHandler
   _server_state: ServerState
   _env_factory: EnvFactory
   _env: tl.Env
   _has_initialized: boolean
   _module_info_manager: ModuleInfoManager
   _open_document_registry: OpenDocumentRegistry
   _has_built: boolean

   record BuildResult
      built_modules: {ModuleInfo}  -- Modules that were actually built
      global_dep_paths: {string: boolean}  -- Set of all global dependency paths
   end

   metamethod __call: function(
      self: BuildHandler, server_state: ServerState, env_factory: EnvFactory,
      module_info_manager: ModuleInfoManager, open_document_registry: OpenDocumentRegistry): BuildHandler
end

function BuildHandler:__init(
      server_state: ServerState, env_factory: EnvFactory, module_info_manager: ModuleInfoManager,
      open_document_registry: OpenDocumentRegistry)
   self._server_state = server_state
   self._env_factory = env_factory
   self._has_initialized = false
   self._module_info_manager = module_info_manager
   self._open_document_registry = open_document_registry
   self._has_built = false
end

function BuildHandler:_invalidate_build_cache_for_module_and_dependents(start_info: ModuleInfo)
   local module_queue: {ModuleInfo} = {}
   local has_processed: {string:boolean} = {}

   table.insert(module_queue, start_info)
   has_processed[start_info.path] = true

   while #module_queue > 0 do
      local module_info = table.remove(module_queue, 1)
      asserts.that(has_processed[module_info.path])

      for dependent_path, _ in pairs(module_info.dependents) do
         if has_processed[dependent_path] == nil then
            has_processed[dependent_path] = true

            local dep_info = self._module_info_manager:try_get_or_create_module_info(dependent_path)

            if dep_info ~= nil then
               table.insert(module_queue, dep_info)
            end
         end
      end

      module_info.requires_build = true
   end
end

function BuildHandler:_on_module_changed(info: ModuleInfo, old_dependencies: {string: boolean})
   if old_dependencies then
      for dep_path, _ in pairs(old_dependencies) do
         local dep_info = self._module_info_manager:try_get_or_create_module_info(dep_path)

         if dep_info then
            dep_info.dependents[info.path] = false
         end
      end
   end

   for dep_path, _ in pairs(info.dependencies) do
      local dep_info = self._module_info_manager:try_get_or_create_module_info(dep_path)

      if dep_info then
         dep_info.dependents[info.path] = true
      end
   end

   self:_invalidate_build_cache_for_module_and_dependents(info)
end

function BuildHandler:sort_files_by_dependency_order(modules: {ModuleInfo}, global_dep_paths: {string: boolean})
   local dep_counts: {string:integer} = {}

   local function get_total_dep_count(file_path: ModuleInfo, visited: {string:boolean}): integer
      if visited[file_path.path] then
         return 0 -- Cycle detection
      end
      visited[file_path.path] = true

      local count = 0
      for dep_path, _ in pairs(file_path.dependencies) do
         local dep_info = self._module_info_manager:try_get_module_info(dep_path)

         if dep_info == nil then
            tracing.warning(_module_name, "Expected dependency info for {}, but none found", {dep_path})
         else
            count = count + 1 + get_total_dep_count(dep_info, visited)
         end
      end

      return count
   end

   -- Cache dependent counts for all files
   for _, info in ipairs(modules) do
      if not dep_counts[info.path] then
         local visited: {string:boolean} = {}
         dep_counts[info.path] = get_total_dep_count(info, visited)
      end
   end


   -- Sort: least dependencies first, lexicographic tiebreaker
   table.sort(modules, function(a: ModuleInfo, b: ModuleInfo): boolean
      local a_is_global = global_dep_paths[a.path] == true
      local b_is_global = global_dep_paths[b.path] == true

      if a_is_global and not b_is_global then
         return true
      elseif not a_is_global and b_is_global then
         return false
      end

      local count_a = dep_counts[a.path]
      local count_b = dep_counts[b.path]

      if count_a ~= count_b then
         return count_a < count_b  -- least dependencies first
      end

      return a.path < b.path  -- Lexicographic tiebreaker for determinism
   end)

   -- Debug: log the dependency order
   tracing.debug(_module_name, "Sorted {} files by dependency order (most dependencies first)", {#modules})

   if tracing.is_trace_enabled(_module_name) then
      for i, info in ipairs(modules) do
         tracing.trace(_module_name, "  {}: {} ({} dependencies)", {i, info.module_name, dep_counts[info.path]})
      end
   end
end

function BuildHandler:_type_check_module(info: ModuleInfo)
   tracing.debug(_module_name, "Type checking module {}", {info.module_name})

   local is_lua = info.path:sub(-4) == ".lua"

   local opts: tl.CheckOptions = {
      feat_lax = is_lua and "on" or "off",
   }

   asserts.is_nil(info.check_result)
   asserts.that(info.requires_build)

   info.check_result = tl.check(
      info.ast, info.path, opts, self._env)

   asserts.is_not_nil(info.check_result)

   info.requires_build = false
end

function BuildHandler:_try_update_unopened_file_with_changes(info: ModuleInfo):boolean
   local modification_time = files_util.try_get_modification_time_ms(info.path)

   if modification_time == info.modification_time then
      tracing.trace(_module_name, "Type checking module {} skipped (unopened file with no changes)", {info.module_name})
      return false
   end

   info.modification_time = modification_time

   local content = files_util.try_read_file_as_text(info.path)

   if content == nil then
      tracing.warning(_module_name, "Failed to read content of unopened file {}", {info.path})
   end

   if not info:try_update_content(content) then
      tracing.trace(_module_name, "Type checking module {} skipped (unopened file with no content changes)", {info.module_name})
      return false
   end

   return true
end

function BuildHandler:_check_unopened_file_for_invalidation(info: ModuleInfo)
   if self:_try_update_unopened_file_with_changes(info) then
      tracing.trace(_module_name, "Detected content change in unopened file {}, updating modification time", {info.path})
      self:_invalidate_build_cache_for_module_and_dependents(info)
   end
end

function BuildHandler:_collect_all_dependencies(subset1: {ModuleInfo}, subset2: {ModuleInfo}): {ModuleInfo}
   local was_queued:{string: boolean} = {}
   local process_queue: {ModuleInfo} = {}

   for _, info in ipairs(subset1) do
      if was_queued[info.path] == nil then
         table.insert(process_queue, info)
         was_queued[info.path] = true
      end
   end

   for _, info in ipairs(subset2) do
      if was_queued[info.path] == nil then
         table.insert(process_queue, info)
         was_queued[info.path] = true
      end
   end

   local subset_with_deps: {ModuleInfo} = {}

   while #process_queue > 0 do
      local info = table.remove(process_queue, 1)
      asserts.that(was_queued[info.path])

      table.insert(subset_with_deps, info)

      for dep_path, _ in pairs(info.dependencies) do
         if was_queued[dep_path] == nil then
            was_queued[dep_path] = true

            local dep_info = self._module_info_manager:try_get_or_create_module_info(dep_path)

            if dep_info ~= nil then
               table.insert(process_queue, dep_info)
            end
         end
      end
   end

   return subset_with_deps
end

function BuildHandler:_get_global_infos():{ModuleInfo}
   local config = self._server_state.config
   local global_module = config.global_env_def

   if not global_module then
      tracing.debug(_module_name, "No global module configured", {})
      return {}
   end

   local req_path, fd = tl.search_module(global_module, true)

   if not req_path then
      tracing.warning(_module_name, "Could not resolve global module: {}", {global_module})
      return {}
   end

   if fd then fd:close() end -- Close file descriptor

   req_path = path_util.canonicalize(req_path)

   local global_info = self._module_info_manager:try_get_or_create_module_info(req_path)

   if global_info == nil then
      return {}
   end

   local all_global_infos = self:_collect_all_dependencies({global_info}, {})
   tracing.debug(_module_name, "Found {} global modules", {#all_global_infos})

   if tracing.is_trace_enabled(_module_name) then
      local all_global_names = {}

      for _, info in ipairs(all_global_infos) do
         table.insert(all_global_names, info.module_name)
      end

      tracing.debug(_module_name, "Global modules: {@}", {all_global_names})
   end

   return all_global_infos
end

function BuildHandler:get_all_modules(): {ModuleInfo}
   local all_files = {}

   for _, source_dir in ipairs(self._server_state.source_dirs) do
      for _, file_path in ipairs(files_util.get_sub_paths_recursive(source_dir, ".tl")) do
         local info = self._module_info_manager:try_get_or_create_module_info(file_path)
         asserts.is_not_nil(info)
         table.insert(all_files, info)
      end
   end

   return all_files
end

function BuildHandler:build(all_modules: {ModuleInfo}, project_subset: {ModuleInfo}): BuildHandler.BuildResult
   for _, info in ipairs(all_modules) do
      if not info.is_opened then
         asserts.is_nil(self._open_document_registry:try_get(info.path))
         self:_check_unopened_file_for_invalidation(info)
      end
   end

   local global_infos = self:_get_global_infos()

   local subset_with_deps:{ModuleInfo}

   if project_subset == nil then
      subset_with_deps = all_modules
   else
      subset_with_deps = self:_collect_all_dependencies(project_subset, global_infos)
   end

   tracing.debug(_module_name, "Found {} modules to consider for build (including dependencies)", {#subset_with_deps})

   if self._has_built then
      local has_invalidated_global = false

      for _, info in ipairs(global_infos) do
         if info.requires_build then
            has_invalidated_global = true
            tracing.debug(_module_name, "Global module {} needs rechecking, invalidating all", {info.module_name})
            break
         end
      end

      if has_invalidated_global then
         for _, info in ipairs(all_modules) do
            info.requires_build = true
         end
         tracing.debug(_module_name, "Invalidated all modules", {})

         self._env = self._env_factory:generate_env()
         tracing.warning(_module_name, "Global environment changed, re-creating env from scratch", {})
      end
   end

   self._has_built = true

   local global_dep_paths: {string: boolean} = {}

   for _, info in ipairs(global_infos) do
      global_dep_paths[info.path] = true
   end

   local modules_to_build = {}

   for _, info in ipairs(subset_with_deps) do
      if info.requires_build then
         -- Need to fully regenerate the ast, tokens, etc.
         -- since teal seems to mutate these every time we type check
         info:clear_teal_cache()
         info.check_result = nil

         -- I'm not sure how to properly invalidate global definitions
         -- Teal seems to store these separtely in the env from other things
         -- So for now we just re-generate the entire env from scratch, when
         -- globals change, instead of trying to figure this out
         if not global_dep_paths[info.path] then
            self._env.modules[info.module_name] = nil
            self._env.loaded[info.path] = nil
         end

         if info.content == nil then
            tracing.warning(_module_name, "Attempting to type check module {} but it has no content (file may have been deleted)", {info.module_name})
         else
            table.insert(modules_to_build, info)
         end
      end
   end

   self:sort_files_by_dependency_order(modules_to_build, global_dep_paths)

   for _, info in ipairs(modules_to_build) do
      self:_type_check_module(info)
   end

   tracing.debug(_module_name, "Ran type check on {} modules", {#modules_to_build})
   return  {
      built_modules = modules_to_build,
      global_dep_paths = global_dep_paths,
   }
end

function BuildHandler:initialize()
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   asserts.is_nil(self._env)
   self._env = self._env_factory:generate_env()

   self._module_info_manager:observe_changes(function(info: ModuleInfo, old_dependencies: {string: boolean})
      self:_on_module_changed(info, old_dependencies)
   end)
end

function BuildHandler:get_env(): tl.Env
   asserts.that(self._has_initialized)
   return self._env
end

class.setup(BuildHandler, "BuildHandler", {
   nilable_members = { '_env' }
})
return BuildHandler
