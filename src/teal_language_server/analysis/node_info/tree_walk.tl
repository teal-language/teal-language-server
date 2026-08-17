-- Cursor and node primitives shared by the rest of the node_info module. These
-- are the smallest operations that still need to know the grammar; everything
-- above them is expressed in terms of these.

local ltreesitter <const> = require("ltreesitter")

local record tree_walk
end

-- Walk down to the leaf containing (y, x), leaving the cursor on it. Returns nil
-- when the position falls between tokens -- every caller treats that as "nothing
-- under the cursor" and bails.
function tree_walk.descend_to_leaf(cursor: ltreesitter.Cursor, y: integer, x: integer): ltreesitter.Node
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

-- ts-teal wraps every expression link in a `prefixexp`, so a node reached via
-- prev_sibling or a field is usually needs to be unwrapped before use
function tree_walk.unwrap_prefixexp(node: ltreesitter.Node): ltreesitter.Node
   while node ~= nil and node:type() == "prefixexp" and node:child_count() == 1 do
      node = node:child(0)
   end
   return node
end

-- Position of a child token (1-indexed), or nil if this node has no such child.
function tree_walk.child_token_position(node: ltreesitter.Node, a: string, b?: string): integer, integer
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
