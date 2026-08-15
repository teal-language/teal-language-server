-- Turning a syntax node into the chain of names it denotes -- {"self",
-- "test_value"} for `self.test_value` -- which is what the tl type report is
-- queried with when a by_pos lookup is unavailable or misses.

local ltreesitter <const> = require("ltreesitter")
local tree_walk <const> = require("teal_language_server.analysis.node_info.tree_walk")

local record token_chain
end

-- Append the dotted/method segments of an expression to `out`, left to right.
-- This walks the tree instead of re-lexing source text, which matters because a
-- node's `source` is not always the chain: ts-teal's `functioncall` spans its
-- arguments too, so splitting `self:m(a, b)` on "." and ":" yields a garbage
-- final segment. The spine always yields exactly the names.
local function append_chain_segments(node: ltreesitter.Node, out: {string})
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
         -- a bare `t`: ts-teal still wraps it in a var, with the name as its
         -- only child rather than as a `key`
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

-- The token chain ending at the cursor, e.g. {"self", "test_value"} for a cursor
-- on `test_value` in `self.test_value.other`. Anchoring on the leaf's *parent*
-- is what makes it stop at the cursor: the enclosing `var` whose `key` is the
-- leaf spans exactly the prefix, so no truncation pass is needed.
function token_chain.for_leaf(leaf: ltreesitter.Node, parent: ltreesitter.Node): {string}
   local out: {string} = {}
   local parent_type = parent:type()
   if parent_type == "var" or parent_type == "functioncall" then
      append_chain_segments(parent, out)
   elseif parent_type == "funcname" then
      -- A funcname is flat -- `a.b.c:d` is seven children, not a nested spine --
      -- so the names are taken by walking it, stopping at the cursor's own.
      --
      -- Not by its `base`/`entry`/`method` fields: ts-teal only labels `entry`
      -- when there is exactly one dotted segment, so `a.b.c:d` yields base=a,
      -- entry=nil, method=d and the middle of the chain silently disappears.
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

-- The names in a nominal type reference -- {"M", "Inner"} for `M.Inner` -- or nil
-- when the annotation is structural ({string}, a union, an inline function type)
-- and so names nothing that could be looked up. Descending only through
-- single-child `type`/`basetype` wrappers is what tells the two apart: a union
-- has two basetype children, a table type has its braces.
function token_chain.for_nominal(type_node: ltreesitter.Node): {string}
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
   local out: {string} = {}
   for child in node:children() do
      if child:type() == "identifier" then
         table.insert(out, child:source())
      end
   end
   return #out > 0 and out or nil
end

return token_chain
