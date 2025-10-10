local _module_name = "open_document"
-- <imports>
local ModuleInfo <const> = require("teal_language_server.module_info")
local ServerState <const> = require("teal_language_server.server_state")
local Uri <const> = require("teal_language_server.uri")
local class <const> = require("teal_language_server.class")
local asserts <const> = require("teal_language_server.asserts")
local tracing <const> = require("teal_language_server.tracing")
local tl <const> = require("tl")

local record OpenDocument
   record NodeInfo
      type: string
      source: string
      parent_type: string
      parent_source: string
      preceded_by: string
      self_type: string
      metamethod __tostring: function(NodeInfo): string
   end

   uri: Uri

   _uri: Uri
   _server_state: ServerState
   _module_info: ModuleInfo

   metamethod __call: function(self: OpenDocument, uri: Uri, server_state: ServerState, module_info: ModuleInfo): OpenDocument
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

function OpenDocument:__init(uri: Uri, server_state: ServerState, module_info: ModuleInfo)
   asserts.is_not_nil(server_state)

   self._uri = uri
   self._server_state = server_state
   self._module_info = module_info
end

function OpenDocument:_try_get_type_report(env: tl.Env): tl.TypeReport
   if env.reporter == nil then
      return nil
   end

   return env.reporter:get_report()
end

local function _get_node_at(ast: tl.Node, y: integer, x: integer): tl.Node
   for _, node in ipairs(ast) do
      if node.y == y and node.x == x then
         return node
      end
   end
end

function OpenDocument:_get_ast_node_at(type_info: tl.TypeInfo, env: tl.Env): tl.Node
   if type_info.file == "" then
      return _get_node_at(self._module_info.ast, type_info.y, type_info.x)
   end

   local loaded_file = env.loaded[type_info.file]
   if loaded_file == nil then return nil end
   return _get_node_at(loaded_file.ast, type_info.y, type_info.x)
end

function OpenDocument:get_function_args_string(type_info: tl.TypeInfo, env: tl.Env): {string}
   local node = self:_get_ast_node_at(type_info, env) as ArgListNode
   if node == nil then return nil end
   local output: {string} = {}
   for _, arg_info in ipairs(node.args) do
      table.insert(output, arg_info.tk)
   end
   return output
end

function OpenDocument:resolve_type_ref(type_number: integer, env: tl.Env): tl.TypeInfo
   local tr <const> = self:_try_get_type_report(env)

   if tr == nil then
      return nil
   end

   local type_info = tr.types[type_number]
   if type_info and type_info.ref then
      return self:resolve_type_ref(type_info.ref, env)
   else
      return type_info
   end
end

function OpenDocument:type_information_for_tokens(tokens: {string}, y: integer, x: integer, env: tl.Env): tl.TypeInfo
   local tr <const> = self:_try_get_type_report(env)

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
   --          local type_info = self:resolve_type_ref(type_ref)

   --          if type_info ~= nil then
   --             tracing.info(_module_name, "Found via quick match at {}, {}", {y, x})
   --             return type_info
   --          end
   --       end
   --    end
   -- end

   local type_info: tl.TypeInfo
   -- try and find it in scope
   local scope_symbols <const> = tl.symbols_in_scope(tr, y+1, x+1, self._uri.path)
   tracing.trace(_module_name, "Looked up symbols at {}, {} for file {} with result: {@}", {y+1, x+1, self._uri.path, scope_symbols})
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
      type_info = self:resolve_type_ref(type_id, env)

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
            type_info = self:resolve_type_ref(type_info.fields[tokens[i]], env)

         elseif type_info.values and i == #tokens then
            type_info = self:resolve_type_ref(type_info.values, env)

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

function OpenDocument:_tree_sitter_token(y: integer, x: integer, depth: integer): OpenDocument.NodeInfo
   tracing.trace(_module_name, "Looking up tree sitter node at {}, {}...", {y, x})

   -- Prevent infinite recursion bugs
   if depth > 100 then
      tracing.warning(_module_name, "Maximum recursion depth reached at position {}, {}", {y, x})
      return nil
   end

   local tree_cursor = self._module_info.tree_cursor

   local moved = tree_cursor:goto_first_child()
   local node = tree_cursor:current_node()

   if moved == false then
      tree_cursor:goto_parent()

      local parent_node = tree_cursor:current_node()

      local out: OpenDocument.NodeInfo = {
         type = node:type(),
         source = node:source(),
         parent_type = parent_node:type(),
         parent_source = parent_node:source()
      }

      -- for completion
      if node:type() == "." or node:type() == ":" then
         -- considered an error and need to get the previous symbol
         local prev = node:prev_sibling()
         if prev then
            out.preceded_by = prev:source()
         else
            parent_node = parent_node:prev_sibling()
            if parent_node:child_count() > 0 then
               -- no previous symbol, so get parent's previous sibling's last child
               out.preceded_by = parent_node:child(parent_node:child_count()-1):source()
            else
               out.preceded_by = parent_node:source()
            end
         end

      -- for function signature
      elseif node:type() == "(" then
         if parent_node:type() == "arguments" then
            tree_cursor:goto_parent()
            local function_call = tree_cursor:current_node():child_by_field_name("called_object")
            if function_call then
               out.preceded_by = function_call:source()
            end

         elseif parent_node:type() == "ERROR" then
            for child in parent_node:children() do
               if child:name() == "index" then
                  out.preceded_by = child:source()
                  break
               end
            end
         end
      end

      if out.preceded_by == "self" or
         out.source:find("self[%.%:]") or
         out.parent_source:find("self[%.%:]") then

         while parent_node:type() ~= "program" do
            tree_cursor:goto_parent()
            parent_node = tree_cursor:current_node()
            tracing.trace(_module_name, "Processing parent node {}", {parent_node:type()})

            if parent_node:type() == "function_statement" then
               local function_name = parent_node:child_by_field_name("name")
               if function_name then
                  local base_name = function_name:child_by_field_name("base")
                  if base_name then
                     out.self_type = base_name:source()
                     break
                  end
               end
            elseif parent_node:type() == "ERROR" then
               tracing.trace(_module_name, "Parent node is in error state, looking for function_name child...")
               -- for some reason you can't get the node by name in an error state, but you can still iterate over to it
               local found = false
               for child in parent_node:children() do
                  tracing.trace(_module_name, "Examining child node {}", {child:type()})
                  if child:name() == "function_name" then
                     out.self_type = child:child_by_field_name("base"):source()
                     found = true
                     break
                  end
               end

               if not found then
                  out.self_type = nil
                  tracing.warning(_module_name, "Failed to find function_name ts node in error node's children", {})
               end

               break
            end
         end
      end

      return out
   end

   local start_point = node:start_point()
   local end_point = node:end_point()

   while moved do
      start_point = node:start_point()
      end_point = node:end_point()

      if y == start_point.row and y == end_point.row then
         if x >= start_point.column and x < end_point.column then
            return self:_tree_sitter_token(y, x, depth + 1)
         end

      elseif y >= start_point.row and y <= end_point.row then
         return self:_tree_sitter_token(y, x, depth + 1)
      end

      moved = tree_cursor:goto_next_sibling()
      node = tree_cursor:current_node()

      tracing.trace(_module_name, "Stepped to next tree sitter sibling: {} ({@} to {@})", {node:type(), node:start_point(), node:end_point()})
   end
end

function OpenDocument:tree_sitter_token(y: integer, x: integer): OpenDocument.NodeInfo
   local tree_cursor = self._module_info.tree_cursor

   tracing.trace(_module_name, "Resetting tree cursor to root", {})
   tree_cursor:reset(self._module_info.tree:root())

   return self:_tree_sitter_token(y, x, 0)
end

class.setup(OpenDocument, "OpenDocument", {
   getters =  {
      uri = function(self:OpenDocument):Uri
         return self._uri
      end
   },
})
return OpenDocument
