local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local table = _tl_compat and _tl_compat.table or table; local _module_name = "teal_helper"

local tl = require("tl")
local ModuleInfo = require("teal_language_server.module_info")
local tracing = require("teal_language_server.tracing")

local teal_helper = {}
















local function _get_node_at(ast, y, x)
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function teal_helper._get_ast_node_at(module_info, type_info, env)
   if type_info.file == "" then
      return _get_node_at(module_info.ast, type_info.y, type_info.x)
   end

   local loaded_file = env.loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast, type_info.y, type_info.x)
end

function teal_helper.get_function_args_string(module_info, type_info, env)
   local node = teal_helper._get_ast_node_at(module_info, type_info, env)
   if node == nil then return nil end
   local output = {}
   for _, arg_info in ipairs(node.args) do
      table.insert(output, arg_info.tk)
   end
   return output
end

function teal_helper.resolve_type_ref(type_number, env)
   local tr = env.reporter and env.reporter:get_report()

   if tr == nil then
      return nil
   end

   local type_info = tr.types[type_number]
   if type_info and type_info.ref then
      return teal_helper.resolve_type_ref(type_info.ref, env)
   else
      return type_info
   end
end

function teal_helper.type_information_for_tokens(module_info, tokens, y, x, env)
   local tr = env.reporter and env.reporter:get_report()

   if tr == nil then
      return nil
   end

























   local type_info

   local scope_symbols = tl.symbols_in_scope(tr, y + 1, x + 1, module_info.path)
   tracing.trace(_module_name, "Looked up symbols at {}, {} for file {} with result: {@}", { y + 1, x + 1, module_info.path, scope_symbols })
   if #tokens == 0 then
      local out = {}
      for key, value in pairs(scope_symbols) do out[key] = value end
      for key, value in pairs(tr.globals) do out[key] = value end
      type_info = {
         fields = out,
      }
      return type_info
   end
   local raw_token = tokens[1]
   tracing.trace(_module_name, "Processing token {} (all: {@})", { raw_token, tokens })
   local type_id = scope_symbols[raw_token]
   if type_id == nil then
      tracing.warning(_module_name, "Failed to find type id for token {}", { raw_token })
   end
   if type_id ~= nil then
      tracing.trace(_module_name, "Matched token {} to type id {}", { raw_token, type_id })
      type_info = teal_helper.resolve_type_ref(type_id, env)

      if type_info == nil then
         tracing.warning(_module_name, "Failed to resolve type ref for id {}", {})
      end
   end


   if type_info == nil then
      type_info = tr.types[tr.globals[raw_token]]

      if type_info == nil then
         tracing.warning(_module_name, "Unable to find type info in global table as well..")
      end
   end

   tracing.trace(_module_name, "Got type info: {@}", { type_info })

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         tracing.trace(_module_name, "tokens[i]: {}", { tokens[i] })

         if type_info.fields then
            type_info = teal_helper.resolve_type_ref(type_info.fields[tokens[i]], env)

         elseif type_info.values and i == #tokens then
            type_info = teal_helper.resolve_type_ref(type_info.values, env)




         end

         if type_info == nil then break end
      end
   end

   if type_info then
      tracing.trace(_module_name, "Successfully found type info", {})
      return type_info
   end

   tracing.warning(_module_name, "Failed to find type info at given position", {})
   return nil
end

function teal_helper.find_symbol_declaration(module_info, symbol_name, env)
   local tr = env.reporter and env.reporter:get_report()
   if not tr then
      tracing.trace(_module_name, "No type report available (env.reporter is nil)")
      return nil
   end

   local file_path = module_info.path
   local symbols = tr.symbols_by_file[file_path]

   if not symbols then
      tracing.trace(_module_name, "No symbols found for file {}", { file_path })
      return nil
   end

   tracing.trace(_module_name, "Searching for symbol '{}' in {} symbols", { symbol_name, #symbols })

   for i = 1, #symbols do
      local sym = symbols[i]
      local y = sym[1]
      local x = sym[2]
      local name = sym[3]

      if name == symbol_name then
         tracing.trace(_module_name, "Found symbol '{}' declared at {}:{}", { symbol_name, y, x })
         return {
            y = y,
            x = x,
            file = file_path,
         }
      end
   end

   tracing.trace(_module_name, "Symbol '{}' not found in current file", { symbol_name })
   return nil
end

return teal_helper
