local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "analysis.node_info"






local ltreesitter = require("ltreesitter")

local NodeInfo = {}














































local declaration_parent_types = {
   ["attnamelist"] = true,
   ["attrib"] = true,
   ["nominal"] = true,
   ["basetype"] = true,



}





local node_kind = {
   ["."] = "dot",
   [":"] = "colon",
   ["("] = "open_paren",
   ["identifier"] = "identifier",
}

local function node_kind_of(node_type)
   return node_kind[node_type] or "other"
end


local function receiver_of(funcname)
   local base_name = funcname:child_by_field_name("base")
   return base_name and base_name:source()
end





local function receiver_name(node)
   local node_type = node:type()
   if node_type == "stat" then
      local function_name = node:child_by_field_name("name")
      if function_name and function_name:type() == "funcname" then
         return receiver_of(function_name)
      end
   elseif node_type == "ERROR" then







      local declares = false
      for child in node:children() do
         if child:type() == "function" then
            declares = true
         elseif child:name() == "funcname" then
            if declares then
               return receiver_of(child)
            end
         elseif child:name() ~= nil then
            declares = false
         end
      end
   end
   return nil
end





local function unwrap_prefixexp(node)
   while node ~= nil and node:type() == "prefixexp" and node:child_count() == 1 do
      node = node:child(0)
   end
   return node
end


local function child_token_position(node, a, b)
   for child in node:children() do
      local child_type = child:type()
      if child_type == a or (b ~= nil and child_type == b) then
         local sp = child:start_point()
         return sp.row + 1, sp.column + 1
      end
   end
   return nil
end






local function append_chain_segments(node, out)
   node = unwrap_prefixexp(node)
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





local function token_chain_for(leaf, parent)
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












local function bypos_key_for(node)
   node = unwrap_prefixexp(node)
   if node == nil then
      return nil
   end
   local node_type = node:type()
   if node_type == "functioncall" then


      if node:child_by_field_name("method") ~= nil then
         local y, x = child_token_position(node, ":")
         if y ~= nil then
            return y, x, 1
         end
      end

      local called = node:child_by_field_name("called_object")
      if called == nil then
         return nil
      end



      local y, x, depth = bypos_key_for(called)
      if y == nil then
         return nil
      end
      return y, x, (depth or 0) + 1
   elseif node_type == "var" then


      local y, x = child_token_position(node, ".", "[")
      if y ~= nil then
         return y, x
      end
   end
   local start_point = node:start_point()
   return start_point.row + 1, start_point.column + 1
end





local function callee_info(call)
   local called = call:child_by_field_name("called_object")
   if called == nil then
      return nil
   end
   local method = call:child_by_field_name("method")
   if method ~= nil then
      local y, x = child_token_position(call, ":")
      return called:source() .. ":" .. method:source(), y, x
   end
   local y, x, depth = bypos_key_for(called)
   return called:source(), y, x, depth
end




local function descend_to_leaf(cursor, y, x)
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
         return descend_to_leaf(cursor, y, x)
      end

      moved = cursor:goto_next_sibling()
      node = cursor:current_node()
   end

   return nil
end


local function fill_completion_trigger(out, leaf, parent)
   local prev = leaf:prev_sibling()
   if prev == nil then



      local sibling = parent:prev_sibling()
      if sibling ~= nil then
         prev = sibling:child_count() > 0 and
         sibling:child(sibling:child_count() - 1) or
         sibling
      end
   end
   if prev ~= nil then
      out.preceded_by = prev:source()


      out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key_for(prev)
   end
end








local function recover_callee_from_error(paren)
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


local function fill_signature_trigger(out, leaf, parent, cursor)
   if parent:type() == "args" then
      if cursor:goto_parent() then
         out.preceded_by, out.bypos_y, out.bypos_x, out.bypos_ret_depth =
         callee_info(cursor:current_node())
      end

   elseif parent:type() == "ERROR" then
      local callee, method_name, colon = recover_callee_from_error(leaf)
      if callee ~= nil then
         if method_name ~= nil then
            out.preceded_by = callee:source() .. ":" .. method_name
            local sp = colon:start_point()
            out.bypos_y, out.bypos_x = sp.row + 1, sp.column + 1
         else
            out.preceded_by = callee:source()
            out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key_for(callee)
         end
      end
   end
end




local function fill_hover_position(out, leaf)
   local prev = leaf:prev_sibling()
   local key_node = (prev and (prev:type() == "." or prev:type() == ":")) and prev or leaf
   local sp = key_node:start_point()
   out.bypos_y = sp.row + 1
   out.bypos_x = sp.column + 1
end










local function first_segment(text)
   return text ~= nil and text:match("^[^%.%:]+") or nil
end

local function references_self(out)
   if out.token_chain_raw ~= nil then
      return out.token_chain_raw[1] == "self"
   end




   return first_segment(out.preceded_by) == "self" or
   first_segment(out.parent_source) == "self"
end



local function fill_self_type(out, parent, cursor)
   if not references_self(out) then
      return
   end




   local node = parent
   while node:type() ~= "chunk" do
      local found = receiver_name(node)
      if found ~= nil then
         out.self_type = found
         return
      end

      if not cursor:goto_parent() then
         return
      end
      node = cursor:current_node()
   end
end



local function fill_resolved_token_chain(out)
   if out.token_chain_raw == nil then
      return
   end
   out.token_chain = out.token_chain_raw
   if out.self_type ~= nil and out.token_chain_raw[1] == "self" then
      out.token_chain = {}
      for i, segment in ipairs(out.token_chain_raw) do
         out.token_chain[i] = i == 1 and out.self_type or segment
      end
   end
end

local function token_at(cursor, y, x)
   local leaf = descend_to_leaf(cursor, y, x)
   if leaf == nil then
      return nil
   end

   cursor:goto_parent()
   local parent = cursor:current_node()
   local parent_type = parent:type()

   local out = {
      kind = node_kind_of(leaf:type()),
      _type = leaf:type(),
      source = leaf:source(),
      _parent_type = parent_type,
      parent_source = parent:source(),
      in_declaration_position = declaration_parent_types[parent_type] == true,
   }

   if out.kind == "dot" or out.kind == "colon" then
      fill_completion_trigger(out, leaf, parent)
   elseif out.kind == "open_paren" then
      fill_signature_trigger(out, leaf, parent, cursor)
   elseif out.kind == "identifier" then




      out.token_chain_raw = token_chain_for(leaf, parent)
      fill_hover_position(out, leaf)
   end

   fill_self_type(out, parent, cursor)
   fill_resolved_token_chain(out)

   return out
end





function NodeInfo.from_cursor(cursor, y, x)
   return token_at(cursor, y, x)
end
















function NodeInfo.enclosing_records(cursor, y, x)
   local names = {}
   if descend_to_leaf(cursor, y, x) == nil then
      return names
   end

   while cursor:goto_parent() do
      if cursor:current_node():type() == "recordbody" then

         if not cursor:goto_parent() then
            break
         end
         local name
         for child in cursor:current_node():children() do
            if child:type() == "identifier" then
               name = child:source()
               break
            end
         end
         if name == nil then
            return {}
         end
         table.insert(names, 1, name)
      end
   end

   return names
end

return NodeInfo
