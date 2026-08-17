local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table







local ltreesitter = require("ltreesitter")

local self_resolution = {}











local function receiver_of(funcname)
   local segments = {}
   for child in funcname:children() do
      local child_type = child:type()
      if child_type == ":" then
         break
      elseif child_type == "identifier" then
         table.insert(segments, child:source())
      end
   end
   if #segments == 0 then
      return nil
   end
   return table.concat(segments, ".")
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

local function first_segment(text)
   return text ~= nil and text:match("^[^%.%:]+") or nil
end









function self_resolution.references_self(token_chain_raw, preceded_by, parent_source)
   if token_chain_raw ~= nil then
      return token_chain_raw[1] == "self"
   end




   return first_segment(preceded_by) == "self" or
   first_segment(parent_source) == "self"
end






function self_resolution.enclosing_receiver(parent, cursor)



   local node = parent
   while node:type() ~= "chunk" do
      local found = receiver_name(node)
      if found ~= nil then
         return found
      end

      if not cursor:goto_parent() then
         return nil
      end
      node = cursor:current_node()
   end
   return nil
end









function self_resolution.resolve_chain(token_chain_raw, self_type)
   if token_chain_raw == nil then
      return nil
   end
   if self_type == nil or token_chain_raw[1] ~= "self" then
      return token_chain_raw
   end
   local resolved = {}
   for segment in self_type:gmatch("[^%.]+") do
      table.insert(resolved, segment)
   end
   for i = 2, #token_chain_raw do
      table.insert(resolved, token_chain_raw[i])
   end
   return resolved
end

return self_resolution
