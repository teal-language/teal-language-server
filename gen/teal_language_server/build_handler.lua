local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; local _module_name = "build_handler"


local tracing = require("teal_language_server.tracing")
local ModuleInfo = require("teal_language_server.module_info")
local asserts = require("teal_language_server.asserts")
local ServerState = require("teal_language_server.server_state")
local class = require("teal_language_server.class")
local EnvFactory = require("teal_language_server.env_factory")
local tl = require("tl")
local ModuleInfoManager = require("teal_language_server.module_info_manager")
local OpenDocumentRegistry = require("teal_language_server.open_document_registry")
local files_util = require("teal_language_server.files_util")
local path_util = require("teal_language_server.path_util")

local BuildHandler = { BuildResult = {} }


















function BuildHandler:__init(
   server_state, env_factory, module_info_manager,
   open_document_registry)
   self._server_state = server_state
   self._env_factory = env_factory
   self._has_initialized = false
   self._module_info_manager = module_info_manager
   self._open_document_registry = open_document_registry
   self._has_built = false
end

function BuildHandler:_invalidate_build_cache_for_module_and_dependents(start_info)
   local module_queue = {}
   local has_processed = {}

   table.insert(module_queue, start_info)
   has_processed[start_info.path] = true

   local build_changed = false

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

      if not module_info.requires_build then
         build_changed = true
      end
      module_info.requires_build = true
   end

   return build_changed
end

function BuildHandler:_on_module_changed(info, old_dependencies)
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

function BuildHandler:sort_files_by_dependency_order(modules, global_dep_paths)
   local dep_counts = {}

   local function get_total_dep_count(file_path, visited)
      if visited[file_path.path] then
         return 0
      end
      visited[file_path.path] = true

      local count = 0
      for dep_path, _ in pairs(file_path.dependencies) do
         local dep_info = self._module_info_manager:try_get_module_info(dep_path)

         if dep_info == nil then
            tracing.warning(_module_name, "Expected dependency info for {}, but none found", { dep_path })
         else
            count = count + 1 + get_total_dep_count(dep_info, visited)
         end
      end

      return count
   end


   for _, info in ipairs(modules) do
      if not dep_counts[info.path] then
         local visited = {}
         dep_counts[info.path] = get_total_dep_count(info, visited)
      end
   end



   table.sort(modules, function(a, b)
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
         return count_a < count_b
      end

      return a.path < b.path
   end)


   tracing.debug(_module_name, "Sorted {} files by dependency order (most dependencies first)", { #modules })

   if tracing.is_trace_enabled(_module_name) then
      for i, info in ipairs(modules) do
         tracing.trace(_module_name, "  {}: {} ({} dependencies)", { i, info.module_name, dep_counts[info.path] })
      end
   end
end

function BuildHandler:_type_check_module(info)
   tracing.trace(_module_name, "Type checking module {}", { info.module_name })

   local is_lua = info.path:sub(-4) == ".lua"

   local opts = {
      feat_lax = is_lua and "on" or "off",
   }

   asserts.is_nil(info.check_result)
   asserts.that(info.requires_build)

   if #info.err_tokens == 0 and #info.parse_errors == 0 then
      info.check_result = tl.check(
      info.ast, info.path, opts, self._env)
   end

   info.requires_build = false
end

function BuildHandler:_try_update_unopened_file_with_changes(info)
   local modification_time = files_util.try_get_modification_time_ms(info.path)

   if modification_time == info.modification_time then
      tracing.trace(_module_name, "Type checking module {} skipped (unopened file with no changes)", { info.module_name })
      return false
   end

   info.modification_time = modification_time

   local content = files_util.try_read_file_as_text(info.path)

   if content == nil then
      tracing.warning(_module_name, "Failed to read content of unopened file {}", { info.path })
   end

   if not info:try_update_content(content) then
      tracing.trace(_module_name, "Type checking module {} skipped (unopened file with no content changes)", { info.module_name })
      return false
   end

   return true
end

function BuildHandler:check_unopened_file_for_invalidation(info)
   if self:_try_update_unopened_file_with_changes(info) then
      tracing.debug(_module_name, "Detected content change in unopened file {}, updating modification time", { info.path })
      return self:_invalidate_build_cache_for_module_and_dependents(info)
   end

   return false
end

function BuildHandler:_collect_all_dependencies(subset1, subset2)
   local was_queued = {}
   local process_queue = {}

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

   local subset_with_deps = {}

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

function BuildHandler:_get_global_infos()
   local config = self._server_state.config
   local global_module = config.global_env_def

   if not global_module then
      tracing.debug(_module_name, "No global module configured", {})
      return {}
   end

   local req_path, fd = tl.search_module(global_module, true)

   if not req_path then
      tracing.warning(_module_name, "Could not resolve global module: {}", { global_module })
      return {}
   end

   if fd then fd:close() end

   req_path = path_util.canonicalize(req_path)

   local global_info = self._module_info_manager:try_get_or_create_module_info(req_path)

   if global_info == nil then
      return {}
   end

   local all_global_infos = self:_collect_all_dependencies({ global_info }, {})
   tracing.debug(_module_name, "Found {} global modules", { #all_global_infos })

   if tracing.is_trace_enabled(_module_name) then
      local all_global_names = {}

      for _, info in ipairs(all_global_infos) do
         table.insert(all_global_names, info.module_name)
      end

      tracing.debug(_module_name, "Global modules: {@}", { all_global_names })
   end

   return all_global_infos
end

function BuildHandler:get_all_modules()
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

function BuildHandler:check_unopened_files_for_invalidation(all_modules)
   local build_changed = false
   for _, info in ipairs(all_modules) do
      if not info.is_opened then
         asserts.is_nil(self._open_document_registry:try_get(info.path))
         if self:check_unopened_file_for_invalidation(info) then
            build_changed = true
         end
      end
   end
   return build_changed
end

function BuildHandler:remove_deleted_modules()
   local deleted_modules = {}


   for file_path, info in pairs(self._module_info_manager.modules) do
      if not files_util.is_file(file_path) then
         tracing.debug(_module_name, "Detected deleted file: {}", { file_path })
         table.insert(deleted_modules, info)
      end
   end

   if #deleted_modules == 0 then
      return false
   end


   for _, info in ipairs(deleted_modules) do
      tracing.debug(_module_name, "Removing deleted module {} from cache", { info.module_name })


      self._env.modules[info.module_name] = nil
      self._env.loaded[info.path] = nil


      self:_invalidate_build_cache_for_module_and_dependents(info)


      self._module_info_manager.modules[info.path] = nil
   end

   tracing.debug(_module_name, "Removed {} deleted modules from cache", { #deleted_modules })
   return true
end

function BuildHandler:build(all_modules, project_subset)
   self:check_unopened_files_for_invalidation(all_modules)

   local global_infos = self:_get_global_infos()

   local subset_with_deps

   if project_subset == nil then
      subset_with_deps = all_modules
   else
      subset_with_deps = self:_collect_all_dependencies(project_subset, global_infos)
   end

   tracing.debug(_module_name, "Found {} modules to consider for build (including dependencies)", { #subset_with_deps })

   if self._has_built then
      local has_invalidated_global = false

      for _, info in ipairs(global_infos) do
         if info.requires_build then
            has_invalidated_global = true
            tracing.debug(_module_name, "Global module {} needs rechecking, invalidating all", { info.module_name })
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

   local global_dep_paths = {}

   for _, info in ipairs(global_infos) do
      global_dep_paths[info.path] = true
   end

   local modules_to_build = {}

   for _, info in ipairs(subset_with_deps) do
      if info.requires_build then


         info:clear_teal_cache()
         info.check_result = nil





         if not global_dep_paths[info.path] then
            self._env.modules[info.module_name] = nil
            self._env.loaded[info.path] = nil
         end

         if info.content == nil then
            tracing.warning(_module_name, "Attempting to type check module {} but it has no content (file may have been deleted)", { info.module_name })
         else
            table.insert(modules_to_build, info)
         end
      end
   end

   self:sort_files_by_dependency_order(modules_to_build, global_dep_paths)

   for _, info in ipairs(modules_to_build) do
      self:_type_check_module(info)
   end

   tracing.debug(_module_name, "Ran type check on {} modules", { #modules_to_build })
   return {
      built_modules = modules_to_build,
      global_dep_paths = global_dep_paths,
   }
end

function BuildHandler:initialize()
   asserts.that(not self._has_initialized)
   self._has_initialized = true

   asserts.is_nil(self._env)
   self._env = self._env_factory:generate_env()

   self._module_info_manager:observe_changes(function(info, old_dependencies)
      self:_on_module_changed(info, old_dependencies)
   end)
end

function BuildHandler:get_env()
   asserts.that(self._has_initialized)
   return self._env
end

class.setup(BuildHandler, "BuildHandler", {
   nilable_members = { '_env' },
})
return BuildHandler
