







local ltreesitter = require("ltreesitter")
local tree_walk = require("teal_language_server.analysis.node_info.tree_walk")

local bypos_key = {}












function bypos_key.for_node(node)
   node = tree_walk.unwrap_prefixexp(node)
   if node == nil then
      return nil
   end
   local node_type = node:type()
   if node_type == "functioncall" then


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



      local y, x, depth = bypos_key.for_node(called)
      if y == nil then
         return nil
      end
      return y, x, (depth or 0) + 1
   elseif node_type == "var" then


      local y, x = tree_walk.child_token_position(node, ".", "[")
      if y ~= nil then
         return y, x
      end
   end
   local start_point = node:start_point()
   return start_point.row + 1, start_point.column + 1
end





function bypos_key.callee_info(call)
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








function bypos_key.callee_from_error(paren)
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
