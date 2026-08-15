-- The position-mapping layer: given a syntax node, where does tl record that
-- expression's type in the report's `by_pos` table? The two trees are joined by
-- raw source position and nothing else, so this is the whole bridge -- an
-- off-by-one here surfaces as a silently wrong (or missing) type, not an error.
--
-- Also resolves what is being called at a call site, which signature help needs
-- both the position and the display text of.

local ltreesitter <const> = require("ltreesitter")
local tree_walk <const> = require("teal_language_server.analysis.node_info.tree_walk")

local record bypos_key
end

-- Map a tree-sitter expression node to the (1-indexed) position where tl records
-- its result type in by_pos, plus the number of return levels to follow so that
-- position holds the callable (rather than the value directly):
--   functioncall  -> the *called object*'s position, ret_depth += 1. tl skips the
--                    call result (a tuple), but records the called object's
--                    function type, whose rets[1] is the result. Nested calls
--                    (f()()) accumulate levels. A method call (`a:b()`) has no
--                    node of its own here, so its ":" is read off the call.
--   var           -> the "."/"[" operator child; the access result lives there
--   anything else -> the node's own start
function bypos_key.for_node(node: ltreesitter.Node): integer, integer, integer
   node = tree_walk.unwrap_prefixexp(node)
   if node == nil then
      return nil
   end
   local node_type = node:type()
   if node_type == "functioncall" then
      -- `a:b()` -- ts-teal has no method_index node, the ":" hangs off the call
      -- itself, and that is where tl records the access result.
      if node:child_by_field_name("method") ~= nil then
         local y, x = tree_walk.child_token_position(node, ":")
         if y ~= nil then
            return y, x, 1
         end
      end

      local called = node:child_by_field_name("called_object")
      if called == nil then
         return nil
      end
      -- resolve the called object's by_pos position and add a return level so
      -- the lookup follows the function's first return value; nested calls
      -- accumulate one level per call.
      local y, x, depth = bypos_key.for_node(called)
      if y == nil then
         return nil
      end
      return y, x, (depth or 0) + 1
   elseif node_type == "var" then
      -- the access result is recorded at the operator: "." for field access,
      -- "[" for bracket indexing
      local y, x = tree_walk.child_token_position(node, ".", "[")
      if y ~= nil then
         return y, x
      end
   end
   local start_point = node:start_point()
   return start_point.row + 1, start_point.column + 1
end

-- Text and by_pos key of the thing being called, for signature help. Under
-- ts-teal `called_object` on a method call holds only the receiver (`s` in
-- `s:rep(`), so the method name has to be stitched back on -- otherwise
-- preceded_by silently degrades from "s:rep" to "s".
function bypos_key.callee_info(call: ltreesitter.Node): string, integer, integer, integer
   local called = call:child_by_field_name("called_object")
   if called == nil then
      return nil
   end
   local method = call:child_by_field_name("method")
   if method ~= nil then
      local y, x = tree_walk.child_token_position(call, ":")
      return called:source() .. ":" .. method:source(), y, x
   end
   local y, x, depth = bypos_key.for_node(called)
   return called:source(), y, x, depth
end

-- Recover the callee of an unclosed call by walking back from the "(" the cursor
-- is actually on. Anchoring on the cursor's own node -- rather than scanning the
-- ERROR node's flattened children from the start, which stops at the first "(" --
-- is what makes the inner paren of `f(g(` resolve `g` instead of `f`.
--
-- Returns the callee, the method name when the shape is `receiver : name (`, and
-- the ":" node itself so its position needs no second scan.
function bypos_key.callee_from_error(paren: ltreesitter.Node): ltreesitter.Node, string, ltreesitter.Node
   local prev = paren:prev_sibling()
   if prev == nil then
      return nil
   end

   if prev:type() == "identifier" then
      local colon = prev:prev_sibling()
      if colon ~= nil and colon:type() == ":" then
         local receiver = colon:prev_sibling()
         if receiver ~= nil then
            return receiver, prev:source(), colon
         end
      end
   end

   return prev, nil, nil
end

return bypos_key
