-- Resolving `self` to the name of the record whose method encloses the cursor.
-- tl's type report has no entry for the word `self` itself, so every request
-- that starts at `self` has to be rewritten to start at that record name before
-- it can be looked up at all.
--
-- These take the fields they read as plain arguments rather than a NodeInfo, so
-- the grammar-specific walk stays independent of the record it ends up filling.

local ltreesitter <const> = require("ltreesitter")

local record self_resolution
end

-- Receiver type named by a `funcname` (the `R` in `function R:m()`).
local function receiver_of(funcname: ltreesitter.Node): string
   local base_name = funcname:child_by_field_name("base")
   return base_name and base_name:source()
end

-- Name of the record `node` declares a method on, if it declares one at all.
-- ts-teal uses a single `stat` node for every kind of statement, so the enclosing
-- function is the one whose `name` field is a `funcname`; statements without one
-- (the `local a = self.` we started from) return nil and the walk continues up.
local function receiver_name(node: ltreesitter.Node): string
   local node_type = node:type()
   if node_type == "stat" then
      local function_name = node:child_by_field_name("name")
      if function_name and function_name:type() == "funcname" then
         return receiver_of(function_name)
      end
   elseif node_type == "ERROR" then
      -- for some reason you can't get the node by name in an error state, but you can still iterate over to it
      --
      -- In a broken parse the children are flattened, so a `funcname` here is not
      -- necessarily a declaration -- a half-typed method *call* (`self:handler(`)
      -- recovers as one too. Only a funcname introduced by the `function` keyword
      -- declares anything; accepting the rest lets call debris shadow the real
      -- enclosing method.
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

local function first_segment(text: string): string
   return text ~= nil and text:match("^[^%.%:]+") or nil
end

-- Whether the expression that will be resolved begins with `self`. That is the
-- only thing self_type is ever used for: substituting the record name into the
-- token chain, or into `preceded_by` for a completion trigger.
--
-- Asking about the resolved segments rather than searching the raw source text
-- keeps the answer independent of where in an expression the cursor sits. The
-- previous four-way substring test fired on `myself.field` from one cursor
-- position and not another, and each new grammar quirk added a clause.
function self_resolution.references_self(token_chain_raw: {string}, preceded_by: string, parent_source: string): boolean
   if token_chain_raw ~= nil then
      return token_chain_raw[1] == "self"
   end
   -- A trigger token has no chain of its own, so fall back to the text of what
   -- will be resolved. Anchoring at the start is the point: `^self` is a real
   -- question about the expression's root, where the old `find("self[%.%:]")`
   -- matched `self.` anywhere inside it, including in `myself.field`.
   return first_segment(preceded_by) == "self"
      or first_segment(parent_source) == "self"
end

-- Name of the record whose method encloses the cursor, or nil if there is none.
-- Only worth calling when references_self says so -- the walk is not free.
--
-- The cursor is mutated in place, so anything derived from the node it currently
-- sits on has to be read before this runs.
function self_resolution.enclosing_receiver(parent: ltreesitter.Node, cursor: ltreesitter.Cursor): string
   -- The node the cursor sits directly under has to be checked before ascending:
   -- under ts-teal a broken method body (`self:` mid-typing) puts the funcname in
   -- the leaf's *immediate* parent, so a walk that moves up first steps over it.
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

-- `self` only becomes a usable type name once the enclosing method is known, so
-- the resolved chain is derived after the enclosing_receiver walk rather than at
-- build time. Returns nil for a nil chain: a trigger token has no chain at all.
function self_resolution.resolve_chain(token_chain_raw: {string}, self_type: string): {string}
   if token_chain_raw == nil then
      return nil
   end
   if self_type == nil or token_chain_raw[1] ~= "self" then
      return token_chain_raw
   end
   local resolved: {string} = {}
   for i, segment in ipairs(token_chain_raw) do
      resolved[i] = i == 1 and self_type or segment
   end
   return resolved
end

return self_resolution
