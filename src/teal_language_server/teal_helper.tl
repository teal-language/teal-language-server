local _module_name = "teal_helper"

local tl <const> = require("tl")
local ModuleInfo <const> = require("teal_language_server.module_info")
local tracing <const> = require("teal_language_server.tracing")

local record teal_helper
end

local record ArgListNode is tl.Node
    record ArgType
        typename: string
    end

    record ArgInfo
        tk: string
        opt: boolean
        argtype: ArgType
    end

    args: {ArgInfo}
end

local function _get_node_at(ast: tl.Node, y: integer, x: integer): tl.Node
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function teal_helper._get_ast_node_at(module_info: ModuleInfo, type_info: tl.TypeInfo, env: tl.Env): tl.Node
   if type_info.file == "" then
      return _get_node_at(module_info.ast, type_info.y, type_info.x)
   end

   local loaded_file = env.loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast, type_info.y, type_info.x)
end

function teal_helper.get_function_args_string(module_info: ModuleInfo, type_info: tl.TypeInfo, env: tl.Env): {string}
   local node = teal_helper._get_ast_node_at(module_info, type_info, env) as ArgListNode
   if node == nil then return nil end
   local output: {string} = {}
   for _, arg_info in ipairs(node.args) do
      table.insert(output, arg_info.tk)
   end
   return output
end

function teal_helper.resolve_type_ref(type_number: integer, env: tl.Env): tl.TypeInfo
   local tr <const> = env.reporter and env.reporter:get_report()

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

function teal_helper.type_information_for_tokens(module_info: ModuleInfo, tokens: {string}, y: integer, x: integer, env: tl.Env): tl.TypeInfo
   local tr <const> = env.reporter and env.reporter:get_report()

   if tr == nil then
      return nil
   end

   -- try the quick get first (works well for self and raw types)
   -- also seems to be necessary when type changes in the middle
   -- of scope (eg. when using assert(x is Foo))

   -- (Commented out because this breaks things more often than it helps currently)
   -- local quick_pos_info = tr.by_pos[self._uri.path]

   -- if quick_pos_info ~= nil then
   --    local quick_line_info = quick_pos_info[y+1]

   --    if quick_line_info ~= nil then
   --       local type_ref = quick_line_info[x+1]

   --       if type_ref ~= nil then
   --          local type_info = teal_helper.resolve_type_ref(type_ref)

   --          if type_info ~= nil then
   --             tracing.info(_module_name, "Found via quick match at {}, {}", {y, x})
   --             return type_info
   --          end
   --       end
   --    end
   -- end

   local type_info: tl.TypeInfo
   -- try and find it in scope
   local scope_symbols <const> = tl.symbols_in_scope(tr, y+1, x+1, module_info.path)
   tracing.trace(_module_name, "Looked up symbols at {}, {} for file {} with result: {@}", {y+1, x+1, module_info.path, scope_symbols})
   if #tokens == 0 then
      local out = {}
      for key, value in pairs(scope_symbols) do out[key] = value end
      for key, value in pairs(tr.globals) do out[key] = value end
      type_info = {
         fields = out
      }
      return type_info
   end
   local raw_token = tokens[1]
   tracing.trace(_module_name, "Processing token {} (all: {@})", {raw_token, tokens})
   local type_id <const> = scope_symbols[raw_token]
   if type_id == nil then
      tracing.warning(_module_name, "Failed to find type id for token {}", {raw_token})
   end
   if type_id ~= nil then
      tracing.trace(_module_name, "Matched token {} to type id {}", {raw_token, type_id})
      type_info = teal_helper.resolve_type_ref(type_id, env)

      if type_info == nil then
         tracing.warning(_module_name, "Failed to resolve type ref for id {}", {})
      end
   end

   -- might be global instead
   if type_info == nil then
      type_info = tr.types[tr.globals[raw_token] ]

      if type_info == nil then
         tracing.warning(_module_name, "Unable to find type info in global table as well..")
      end
   end

   tracing.trace(_module_name, "Got type info: {@}", {type_info})

   if type_info and #tokens > 1 then
      for i = 2, #tokens do
         tracing.trace(_module_name, "tokens[i]: {}", {tokens[i]})

         if type_info.fields then
            type_info = teal_helper.resolve_type_ref(type_info.fields[tokens[i]], env)

         elseif type_info.values and i == #tokens then
            type_info = teal_helper.resolve_type_ref(type_info.values, env)

         -- else
         --    tracing.warning(_module_name, "Something odd is going on here bruv '{}'", type_info)

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

function teal_helper.find_symbol_declaration(module_info: ModuleInfo, symbol_name: string, env: tl.Env): tl.TypeInfo
   local tr <const> = env.reporter and env.reporter:get_report()
   if not tr then
      tracing.trace(_module_name, "No type report available (env.reporter is nil)")
      return nil
   end

   local file_path <const> = module_info.path
   local symbols <const> = tr.symbols_by_file[file_path] as {tl.TypeReport.Symbol}

   if not symbols then
      tracing.trace(_module_name, "No symbols found for file {}", {file_path})
      return nil
   end

   tracing.trace(_module_name, "Searching for symbol '{}' in {} symbols", {symbol_name, #symbols})

   for i = 1, #symbols do
      local sym <const> = symbols[i]
      local y <const> = sym[1] as integer
      local x <const> = sym[2] as integer
      local name <const> = sym[3] as string

      if name == symbol_name then
         tracing.trace(_module_name, "Found symbol '{}' declared at {}:{}", {symbol_name, y, x})
         return {
            y = y,
            x = x,
            file = file_path
         }
      end
   end

   tracing.trace(_module_name, "Symbol '{}' not found in current file", {symbol_name})
   return nil
end

return teal_helper
