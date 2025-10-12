local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local _module_name = "tree_sitter_helper"

local ModuleInfo = require("teal_language_server.module_info")
local asserts = require("teal_language_server.asserts")
local tracing = require("teal_language_server.tracing")
local ltreesitter = require("ltreesitter")

local tree_sitter_helper = { LeafNodeInfo = {}, NodeInfo = {} }


















function tree_sitter_helper._guess_leaf_info_at(module_info, y, x, depth)
   asserts.that(depth < 200)

   local tree_cursor = module_info.tree_cursor

   local moved = tree_cursor:goto_first_child()
   local node = tree_cursor:current_node()
   local node_type = node:type()

   if not moved then
      tracing.trace(_module_name, "Found leaf node: {} ({@} to {@})", { node_type, node:start_point(), node:end_point() })

      tree_cursor:goto_parent()

      local parent_node = tree_cursor:current_node()
      local parent_node_type = parent_node:type()

      tracing.trace(_module_name, "Found leaf node.  Moving back up to parent node: {} ({@} to {@})", { parent_node_type, parent_node:start_point(), parent_node:end_point() })

      local out = {
         type = node_type,
         source = node:source(),
         parent_type = parent_node_type,
         parent_source = parent_node:source(),
         parent_start = parent_node:start_point(),
         parent_end = parent_node:end_point(),
      }


      if node_type == "." or node_type == ":" then

         local prev = node:prev_sibling()
         if prev then
            out.preceded_by = prev:source()
         else
            parent_node = parent_node:prev_sibling()
            parent_node_type = parent_node:type()

            if parent_node:child_count() > 0 then

               out.preceded_by = parent_node:child(parent_node:child_count() - 1):source()
            else
               out.preceded_by = parent_node:source()
            end
         end

      elseif node_type == "(" then
         if parent_node_type == "arguments" then
            tree_cursor:goto_parent()
            local function_call = tree_cursor:current_node():child_by_field_name("called_object")
            if function_call then
               out.preceded_by = function_call:source()
            end

         elseif parent_node_type == "ERROR" then
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

         while parent_node_type ~= "program" do
            tree_cursor:goto_parent()
            parent_node = tree_cursor:current_node()
            parent_node_type = parent_node:type()

            tracing.trace(_module_name, "Processing parent node {}", { parent_node_type })

            if parent_node_type == "function_statement" then
               local function_name = parent_node:child_by_field_name("name")
               if function_name then
                  local base_name = function_name:child_by_field_name("base")
                  if base_name then
                     out.self_type = base_name:source()
                     break
                  end
               end
            elseif parent_node_type == "ERROR" then
               tracing.trace(_module_name, "Parent node is in error state, looking for function_name child...")

               local found = false
               for child in parent_node:children() do
                  local child_type = child:type()
                  tracing.trace(_module_name, "Examining child node {}", { child_type })
                  if child:name() == "function_name" then
                     out.self_type = child:child_by_field_name("base"):source()
                     found = true
                     break
                  end
               end

               if not found then

                  tree_cursor:goto_parent()
                  local function_statement = tree_cursor:current_node()
                  local function_statement_type = function_statement:type()

                  if function_statement_type == "function_statement" then
                     tracing.trace(_module_name, "Looking for function_name in parent function_statement", {})
                     local function_name = function_statement:child_by_field_name("name")
                     if function_name then
                        local base_node = function_name:child_by_field_name("base")
                        if base_node then
                           out.self_type = base_node:source()
                           found = true
                           tracing.trace(_module_name, "Found self_type from parent function_statement: {}", { out.self_type })
                        else
                           tracing.trace(_module_name, "function_name has no base field", {})
                        end
                     else
                        tracing.trace(_module_name, "function_statement has no name field", {})
                     end
                  else
                     tracing.trace(_module_name, "Parent is not function_statement: {}", { function_statement_type })
                  end
               end

               if not found then
                  out.self_type = nil
                  tracing.warning(_module_name, "Failed to find function_name ts node anywhere", {})
               end

               break
            end
         end
      end

      return out
   end

   while moved do
      local start_point = node:start_point()
      local end_point = node:end_point()

      asserts.that(start_point.row <= end_point.row)

      local is_contained

      if y == start_point.row and y == end_point.row then
         asserts.that(start_point.column <= end_point.column)
         is_contained = x >= start_point.column and x < end_point.column
      else
         is_contained = y >= start_point.row and y <= end_point.row
      end

      if is_contained then
         tracing.trace(_module_name, "Node {} ({@} to {@}) contains position {}, {}", { node_type, start_point, end_point, y, x })
         return tree_sitter_helper._guess_leaf_info_at(module_info, y, x, depth + 1)
      end

      moved = tree_cursor:goto_next_sibling()
      node = tree_cursor:current_node()
      node_type = node:type()
   end
end

function tree_sitter_helper.guess_leaf_info_at(module_info, y, x)
   local tree_cursor = module_info.tree_cursor

   tracing.trace(_module_name, "Resetting tree cursor to root", {})
   tree_cursor:reset(module_info.tree:root())

   return tree_sitter_helper._guess_leaf_info_at(module_info, y, x, 0)
end

function tree_sitter_helper._get_info_at(module_info, y, x, depth)
   asserts.that(depth < 200)

   local tree_cursor = module_info.tree_cursor

   local moved = tree_cursor:goto_first_child()
   local node = tree_cursor:current_node()
   local node_type = node:type()

   if not moved then
      tracing.trace(_module_name, "Found leaf node: {} ({@} to {@})", { node_type, node:start_point(), node:end_point() })

      return {
         type = node_type,
         start = node:start_point(),
         stop = node:end_point(),
      }
   end

   local start_node = node
   local start_node_type = node_type

   while moved do
      local start_point = node:start_point()
      local end_point = node:end_point()

      asserts.that(start_point.row <= end_point.row)

      local is_contained

      if y == start_point.row and y == end_point.row then
         asserts.that(start_point.column <= end_point.column)
         is_contained = x >= start_point.column and x < end_point.column
      else
         is_contained = y >= start_point.row and y <= end_point.row
      end

      if is_contained then
         tracing.trace(_module_name, "Node {} ({@} to {@}) contains position {}, {}", { node_type, start_point, end_point, y, x })
         local result = tree_sitter_helper._get_info_at(module_info, y, x, depth + 1)

         if result ~= nil then
            return result
         end
      end

      moved = tree_cursor:goto_next_sibling()
      node = tree_cursor:current_node()
      node_type = node:type()
   end

   return {
      type = start_node_type,
      start = start_node:start_point(),
      stop = start_node:end_point(),
   }
end

function tree_sitter_helper.get_info_at(module_info, y, x)
   local tree_cursor = module_info.tree_cursor

   tracing.trace(_module_name, "Resetting tree cursor to root", {})
   tree_cursor:reset(module_info.tree:root())

   return tree_sitter_helper._get_info_at(module_info, y, x, 0)
end

return tree_sitter_helper
