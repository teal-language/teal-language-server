local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local table = _tl_compat and _tl_compat.table or table; local _module_name = "analysis.node_info"














local ltreesitter = require("ltreesitter")

local tree_walk = require("teal_language_server.analysis.node_info.tree_walk")
local token_chain = require("teal_language_server.analysis.node_info.token_chain")
local bypos_key = require("teal_language_server.analysis.node_info.bypos_key")
local self_resolution = require("teal_language_server.analysis.node_info.self_resolution")

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


      out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key.for_node(prev)
   end
end


local function fill_signature_trigger(out, leaf, parent, cursor)
   if parent:type() == "args" then
      if cursor:goto_parent() then
         out.preceded_by, out.bypos_y, out.bypos_x, out.bypos_ret_depth =
         bypos_key.callee_info(cursor:current_node())
      end

   elseif parent:type() == "ERROR" then
      local callee, method_name, colon = bypos_key.callee_from_error(leaf)
      if callee ~= nil then
         if method_name ~= nil then
            out.preceded_by = callee:source() .. ":" .. method_name
            local sp = colon:start_point()
            out.bypos_y, out.bypos_x = sp.row + 1, sp.column + 1
         else
            out.preceded_by = callee:source()
            out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key.for_node(callee)
         end
      end
   end
end











local function fill_partype_name(out, leaf, annotation)
   local start_point = annotation:start_point()
   out.bypos_y = start_point.row + 1
   out.bypos_x = start_point.column + 1




   out.token_chain_raw = token_chain.for_nominal(annotation) or { leaf:source() }
end




local function fill_hover_position(out, leaf)
   local prev = leaf:prev_sibling()
   local key_node = (prev and (prev:type() == "." or prev:type() == ":")) and prev or leaf
   local sp = key_node:start_point()
   out.bypos_y = sp.row + 1
   out.bypos_x = sp.column + 1
end

local function token_at(cursor, y, x)
   local leaf = tree_walk.descend_to_leaf(cursor, y, x)
   if leaf == nil then
      return nil
   end

   local leaf_start = leaf:start_point()
   local leaf_end = leaf:end_point()

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
      start_y = leaf_start.row,
      start_x = leaf_start.column,
      end_y = leaf_end.row,
      end_x = leaf_end.column,
   }

   if out.kind == "dot" or out.kind == "colon" then
      fill_completion_trigger(out, leaf, parent)
   elseif out.kind == "open_paren" then
      fill_signature_trigger(out, leaf, parent, cursor)
   elseif out.kind == "identifier" then


      local annotation
      if parent_type == "partype" then
         annotation = parent:child_by_field_name("type")
      end

      if annotation ~= nil then
         fill_partype_name(out, leaf, annotation)
      else




         out.token_chain_raw = token_chain.for_leaf(leaf, parent)
         fill_hover_position(out, leaf)
      end
   end



   if self_resolution.references_self(out.token_chain_raw, out.preceded_by, out.parent_source) then
      out.self_type = self_resolution.enclosing_receiver(parent, cursor)
   end
   out.token_chain = self_resolution.resolve_chain(out.token_chain_raw, out.self_type)

   return out
end





function NodeInfo.from_cursor(cursor, y, x)
   return token_at(cursor, y, x)
end




















function NodeInfo.name_at_cursor(cursor, y, x)


   local root = cursor:current_node()

   local out = token_at(cursor, y, x)
   if x == 0 or (out ~= nil and out.kind == "identifier") then
      return out
   end

   cursor:reset(root)
   local before = token_at(cursor, y, x - 1)
   if before ~= nil and before.kind == "identifier" then
      return before
   end
   return out
end
















function NodeInfo.enclosing_records(cursor, y, x)
   local names = {}
   if tree_walk.descend_to_leaf(cursor, y, x) == nil then
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
