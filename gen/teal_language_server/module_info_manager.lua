local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "module_info_manager"


local path_util = require("teal_language_server.path_util")
local util = require("teal_language_server.util")
local asserts = require("teal_language_server.asserts")
local class = require("teal_language_server.class")
local ModuleInfo = require("teal_language_server.module_info")
local files_util = require("teal_language_server.files_util")
local tracing = require("teal_language_server.tracing")
local ServerState = require("teal_language_server.server_state")
local tl = require("tl")
local Uri = require("teal_language_server.uri")

local ModuleInfoManager = {}









function ModuleInfoManager:__init(server_state)
   self._modules = {}
   self._server_state = server_state
   self._change_listeners = {}
end

function ModuleInfoManager:_try_get_module_name(source_dir, file_path)
   if not util.string_starts_with(file_path, source_dir) then
      return nil
   end

   local relative_path = file_path:sub(#source_dir + 2)

   if util.string_ends_with(relative_path, ".d.tl") then
      relative_path = relative_path:sub(1, -6)
   else
      asserts.that(util.string_ends_with(relative_path, ".tl"))
      relative_path = relative_path:sub(1, -4)
   end

   local module_name = relative_path:gsub("[/\\]", ".")
   return module_name
end

function ModuleInfoManager:get_module_info(file_path)
   local info = self._modules[file_path]
   asserts.is_not_nil(info)
   return info
end

function ModuleInfoManager:try_get_module_info(file_path)
   return self._modules[file_path]
end

function ModuleInfoManager:try_get_or_create_module_info(file_path)
   local info = self._modules[file_path]

   if info == nil then
      local module_name = nil

      for _, source_dir in ipairs(self._server_state.source_dirs) do
         module_name = self:_try_get_module_name(source_dir, file_path)
         if module_name ~= nil then
            break
         end
      end

      if module_name == nil then
         tracing.warning(_module_name, "Could not determine module name for file {}", { file_path })
         return nil
      end

      info = ModuleInfo(file_path, module_name)
      self._modules[file_path] = info
   end

   return info
end

function ModuleInfoManager:observe_changes(handler)
   table.insert(self._change_listeners, handler)
end

function ModuleInfoManager:_extract_dependencies(info)

   local file_deps = {}
   local num_found = 0

   for _, req_name in ipairs(info.required_modules) do
      local req_path, fd = tl.search_module(req_name, true)

      if req_path then
         if fd then fd:close() end

         req_path = path_util.canonicalize(req_path)

         if file_deps[req_path] == nil then
            if files_util.is_file(req_path) then
               file_deps[req_path] = true
               num_found = num_found + 1
               tracing.trace(_module_name, "Found project dependency: {} -> {}", { req_name, req_path })
            else
               tracing.warning(_module_name, "Could not get file attributes for dependency: {} (resolved from {})", { req_path, req_name })
            end
         end
      else
         tracing.warning(_module_name, "Could not resolve module: {}", { req_name })
      end
   end

   return file_deps
end

function ModuleInfoManager:_try_update_content(info, content)
   if not info:try_update_content(content) then
      return
   end

   local old_dependencies = info.dependencies

   if info.content == nil then
      info.dependencies = {}
   else
      info.dependencies = self:_extract_dependencies(info)
   end

   for _, handler in ipairs(self._change_listeners) do
      handler(info, old_dependencies)
   end
end

function ModuleInfoManager:on_opened(file_path, content, uri)
   local info = self:try_get_or_create_module_info(file_path)

   if info == nil then
      return
   end

   info.is_opened = true

   info.modification_time = nil
   info.uri = uri

   self:_try_update_content(info, content)
end

function ModuleInfoManager:on_changed(file_path, content, uri)
   local info = self:try_get_or_create_module_info(file_path)

   if info == nil then
      return
   end

   asserts.that(info.is_opened)
   asserts.is_nil(info.modification_time)
   asserts.that(info.uri.path == uri.path)

   self:_try_update_content(info, content)
end

function ModuleInfoManager:on_closed(file_path)
   local info = self:try_get_or_create_module_info(file_path)

   if info == nil then
      return
   end

   asserts.that(info.is_opened)
   info.is_opened = false


   info.modification_time = files_util.try_get_modification_time_ms(file_path)
   info.uri = nil

   local content = files_util.try_read_file_as_text(file_path)
   self:_try_update_content(info, content)
end

function ModuleInfoManager:initialize()
   local populate_start = os.clock()

   tracing.debug(_module_name, "Initializing module info cache", {})

   for _, source_dir in ipairs(self._server_state.source_dirs) do
      for _, file_path in ipairs(files_util.get_sub_paths_recursive(source_dir, ".tl")) do
         local module_name = self:_try_get_module_name(source_dir, file_path)
         asserts.is_not_nil(module_name)
         local info = ModuleInfo(file_path, module_name)

         asserts.is_nil(self._modules[file_path])
         self._modules[file_path] = info

         info.modification_time = files_util.try_get_modification_time_ms(file_path)
         local content = files_util.try_read_file_as_text(file_path)

         local was_updated = info:try_update_content(content)
         asserts.that(was_updated)

         if content then
            info.dependencies = self:_extract_dependencies(info)
         else
            tracing.warning(_module_name, "Could not read file: {}", { file_path })
            info.dependencies = {}
         end
      end
   end

   for file_path, info in pairs(self._modules) do
      for dep_path, _ in pairs(info.dependencies) do
         local dep_info = self._modules[dep_path]

         if dep_info == nil then
            tracing.warning(_module_name, "Expected to find dependency file {} in module cache, but it was not found", { dep_path })
         else
            dep_info.dependents[file_path] = true
         end
      end
   end

   local populate_time = (os.clock() - populate_start) * 1000
   tracing.debug(_module_name, "Cache initialization completed in {%.3f}ms", { populate_time })
end

class.setup(ModuleInfoManager, "ModuleInfoManager", {
   getters = {
      modules = function(self)
         return self._modules
      end,
   },
})
return ModuleInfoManager
