



local ltreesitter = require("ltreesitter")

local tree_walk = {}





function tree_walk.descend_to_leaf(cursor, y, x)
   local moved = cursor:goto_first_child()
   local node = cursor:current_node()

   if moved == false then
      return node
   end

   while moved do
      local start_point = node:start_point()
      local end_point = node:end_point()

      local after_start = y > start_point.row or (y == start_point.row and x >= start_point.column)
      local before_end = y < end_point.row or (y == end_point.row and x < end_point.column)
      if after_start and before_end then
         return tree_walk.descend_to_leaf(cursor, y, x)
      end

      moved = cursor:goto_next_sibling()
      node = cursor:current_node()
   end

   return nil
end





function tree_walk.unwrap_prefixexp(node)
   while node ~= nil and node:type() == "prefixexp" and node:child_count() == 1 do
      node = node:child(0)
   end
   return node
end


function tree_walk.child_token_position(node, a, b)
   for child in node:children() do
      local child_type = child:type()
      if child_type == a or (b ~= nil and child_type == b) then
         local sp = child:start_point()
         return sp.row + 1, sp.column + 1
      end
   end
   return nil
end

return tree_walk
