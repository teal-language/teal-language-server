local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local table = _tl_compat and _tl_compat.table or table



local ltreesitter = require("ltreesitter")
local tree_walk = require("teal_language_server.analysis.node_info.tree_walk")

local token_chain = {}







local function append_chain_segments(node, out)
   node = tree_walk.unwrap_prefixexp(node)
   if node == nil then
      return
   end
   local node_type = node:type()
   if node_type == "var" then
      local object = node:child_by_field_name("object")
      if object ~= nil then
         append_chain_segments(object, out)
      end
      local key = node:child_by_field_name("key")
      if key ~= nil then
         table.insert(out, key:source())
      elseif object == nil then


         for child in node:children() do
            if child:type() == "identifier" then
               table.insert(out, child:source())
               break
            end
         end
      end
   elseif node_type == "functioncall" then
      append_chain_segments(node:child_by_field_name("called_object"), out)
      local method = node:child_by_field_name("method")
      if method ~= nil then
         table.insert(out, method:source())
      end
   elseif node_type == "identifier" then
      table.insert(out, node:source())
   end
end





function token_chain.for_leaf(leaf, parent)
   local out = {}
   local parent_type = parent:type()
   if parent_type == "var" or parent_type == "functioncall" then
      append_chain_segments(parent, out)
   elseif parent_type == "funcname" then






      local leaf_start = leaf:start_point()
      for child in parent:children() do
         if child:type() == "identifier" then
            table.insert(out, child:source())
            local child_start = child:start_point()
            if child_start.row == leaf_start.row and child_start.column == leaf_start.column then
               break
            end
         end
      end
   else
      table.insert(out, leaf:source())
   end
   return out
end






function token_chain.for_nominal(type_node)
   local node = type_node
   while node ~= nil and (node:type() == "type" or node:type() == "basetype") do
      if node:child_count() ~= 1 then
         return nil
      end
      node = node:child(0)
   end
   if node == nil or node:type() ~= "nominal" then
      return nil
   end
   local out = {}
   for child in node:children() do
      if child:type() == "identifier" then
         table.insert(out, child:source())
      end
   end
   return #out > 0 and out or nil
end

return token_chain
