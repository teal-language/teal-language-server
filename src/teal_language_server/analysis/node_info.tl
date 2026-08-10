local _module_name = "analysis.node_info"

-- The grammar boundary. Everything that knows a tree-sitter node type name lives
-- in this file; nothing outside it should compare against one. Handlers read the
-- normalized `kind` and the flags below instead, so swapping the grammar is a
-- change to this module rather than to every handler.

local ltreesitter <const> = require("ltreesitter")

local record NodeInfo
   -- What the cursor is sitting on, normalized. This is the ONLY thing
   -- handlers should branch on: it is defined here, inside the region that
   -- knows the grammar, so a grammar swap cannot silently change its meaning.
   enum NodeKind
      "dot"          -- "." -- field access, completion trigger
      "colon"        -- ":" -- method access, completion trigger
      "open_paren"   -- "(" -- signature help trigger
      "identifier"   -- a name: hover, goto-definition, mid-word completion
      "other"        -- anything else; handlers bail
   end
   kind: NodeKind
   -- `type` and `parent_type` are raw tree-sitter node type names. They change
   -- wholesale if the grammar is swapped, so they are debug/logging detail
   -- only -- never branch on them. Branch on `kind` above.
   _type: string
   source: string
   _parent_type: string
   parent_source: string
   -- The chain of names ending at the cursor, e.g. {"self", "test_value"} for
   -- a cursor on `test_value` in `self.test_value.other`. Built by walking the
   -- tree, so it stays correct where a node's source text spans more than the
   -- chain does -- feed this to type_information_for_tokens.
   token_chain: {string}      -- a leading `self` resolved to the record name
   token_chain_raw: {string}  -- `self` kept literal, for symbol lookups
   -- the cursor sits in a declaration or type-annotation position, where
   -- offering in-scope completions would be noise
   in_declaration_position: boolean
   preceded_by: string
   self_type: string
   -- the (1-indexed) position to look this request's type up in by_pos:
   -- for completion the preceding expression's result, for signature help the
   -- called object, for hover the identifier under the cursor
   bypos_y: integer
   bypos_x: integer
   -- when the preceding expression is a function call, bypos_(y,x) points at
   -- the *called object* (whose function type stock tl does record) rather than
   -- the call result (a tuple stock tl skips); this holds the number of return
   -- levels to follow to recover the call's result type. Nested calls (f()())
   -- accumulate levels, one rets[1] hop per call.
   bypos_ret_depth: integer
   metamethod __tostring: function(NodeInfo): string

   from_cursor: function(ltreesitter.Cursor, integer, integer): NodeInfo
end

local declaration_parent_types <const>: {string:boolean} = {
   ["attnamelist"] = true,  -- `local abc = ...` declarator
   ["attrib"] = true,       -- the `<const>` / `<close>` attribute
   ["nominal"] = true,      -- `local abc: MyType`
   ["basetype"] = true,     -- `local abc: string` / `{string:number}`
   -- deliberately NOT recordkey/parname: tree-sitter-teal did not suppress
   -- completion at a record field name or a parameter name, and widening that
   -- here would be a behaviour change smuggled in under a grammar swap
}

-- Collapse a raw tree-sitter node type into the handler-facing `Kind`. These four
-- tokens happen to be spelled the same in tree-sitter-teal and ts-teal, but that
-- is exactly the assumption worth pinning in one place rather than scattering
-- across the handlers.
local node_kind <const>: {string:NodeInfo.NodeKind} = {
   ["."] = "dot",
   [":"] = "colon",
   ["("] = "open_paren",
   ["identifier"] = "identifier",
}

local function node_kind_of(node_type: string): NodeInfo.NodeKind
   return node_kind[node_type] or "other"
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

-- ts-teal wraps every expression link in a `prefixexp`, so a node reached via
-- prev_sibling or a field is usually one or more wrappers away from the thing we
-- actually want to dispatch on. Failing to unwrap does not error -- it silently
-- falls through to "the node's own start" and returns a wrong by_pos key.
local function unwrap_prefixexp(node: ltreesitter.Node): ltreesitter.Node
   while node ~= nil and node:type() == "prefixexp" and node:child_count() == 1 do
      node = node:child(0)
   end
   return node
end

-- Position of a child token (1-indexed), or nil if this node has no such child.
local function child_token_position(node: ltreesitter.Node, a: string, b?: string): integer, integer
   for child in node:children() do
      local child_type = child:type()
      if child_type == a or (b ~= nil and child_type == b) then
         local sp = child:start_point()
         return sp.row + 1, sp.column + 1
      end
   end
   return nil
end

-- Append the dotted/method segments of an expression to `out`, left to right.
-- This walks the tree instead of re-lexing source text, which matters because a
-- node's `source` is not always the chain: ts-teal's `functioncall` spans its
-- arguments too, so splitting `self:m(a, b)` on "." and ":" yields a garbage
-- final segment. The spine always yields exactly the names.
local function append_chain_segments(node: ltreesitter.Node, out: {string})
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
local function token_chain_for(leaf: ltreesitter.Node, parent: ltreesitter.Node): {string}
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
local function bypos_key_for(node: ltreesitter.Node): integer, integer, integer
   node = unwrap_prefixexp(node)
   if node == nil then
      return nil
   end
   local node_type = node:type()
   if node_type == "functioncall" then
      -- `a:b()` -- ts-teal has no method_index node, the ":" hangs off the call
      -- itself, and that is where tl records the access result.
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
      -- resolve the called object's by_pos position and add a return level so
      -- the lookup follows the function's first return value; nested calls
      -- accumulate one level per call.
      local y, x, depth = bypos_key_for(called)
      if y == nil then
         return nil
      end
      return y, x, (depth or 0) + 1
   elseif node_type == "var" then
      -- the access result is recorded at the operator: "." for field access,
      -- "[" for bracket indexing
      local y, x = child_token_position(node, ".", "[")
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
local function callee_info(call: ltreesitter.Node): string, integer, integer, integer
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

-- Walk down to the leaf containing (y, x), leaving the cursor on it. Returns nil
-- when the position falls between tokens -- every caller treats that as "nothing
-- under the cursor" and bails.
local function descend_to_leaf(cursor: ltreesitter.Cursor, y: integer, x: integer): ltreesitter.Node
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

-- Completion: the type to complete against is the expression before the trigger.
local function fill_completion_trigger(out: NodeInfo, leaf: ltreesitter.Node, parent: ltreesitter.Node)
   local prev = leaf:prev_sibling()
   if prev == nil then
      -- ERROR recovery can reparent the trigger character, leaving it with no
      -- previous sibling; the symbol is then the last thing under the parent's
      -- previous sibling.
      local sibling = parent:prev_sibling()
      if sibling ~= nil then
         prev = sibling:child_count() > 0
            and sibling:child(sibling:child_count() - 1)
            or sibling
      end
   end
   if prev ~= nil then
      out.preceded_by = prev:source()
      -- record where the preceding expression's result type lives in by_pos so
      -- completion can resolve it directly (calls, chains, dotted access)
      out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key_for(prev)
   end
end

-- Recover the callee of an unclosed call by walking back from the "(" the cursor
-- is actually on. Anchoring on the cursor's own node -- rather than scanning the
-- ERROR node's flattened children from the start, which stops at the first "(" --
-- is what makes the inner paren of `f(g(` resolve `g` instead of `f`.
--
-- Returns the callee, the method name when the shape is `receiver : name (`, and
-- the ":" node itself so its position needs no second scan.
local function recover_callee_from_error(paren: ltreesitter.Node): ltreesitter.Node, string, ltreesitter.Node
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

-- Signature help: resolve what is being called.
local function fill_signature_trigger(out: NodeInfo, leaf: ltreesitter.Node, parent: ltreesitter.Node, cursor: ltreesitter.Cursor)
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

-- Hover: a cursor on an identifier resolves via by_pos. A field access (preceded
-- by "." / ":") has its result recorded at the operator, so look there; a plain
-- variable resolves at its own position.
local function fill_hover_position(out: NodeInfo, leaf: ltreesitter.Node)
   local prev = leaf:prev_sibling()
   local key_node = (prev and (prev:type() == "." or prev:type() == ":")) and prev or leaf
   local sp = key_node:start_point()
   out.bypos_y = sp.row + 1
   out.bypos_x = sp.column + 1
end

-- Whether the expression this NodeInfo will be resolved against begins with
-- `self`. That is the only thing self_type is ever used for: substituting the
-- record name into the token chain, or into `preceded_by` for a completion
-- trigger.
--
-- Asking about the resolved segments rather than searching the raw source text
-- keeps the answer independent of where in an expression the cursor sits. The
-- previous four-way substring test fired on `myself.field` from one cursor
-- position and not another, and each new grammar quirk added a clause.
local function first_segment(text: string): string
   return text ~= nil and text:match("^[^%.%:]+") or nil
end

local function references_self(out: NodeInfo): boolean
   if out.token_chain_raw ~= nil then
      return out.token_chain_raw[1] == "self"
   end
   -- A trigger token has no chain of its own, so fall back to the text of what
   -- will be resolved. Anchoring at the start is the point: `^self` is a real
   -- question about the expression's root, where the old `find("self[%.%:]")`
   -- matched `self.` anywhere inside it, including in `myself.field`.
   return first_segment(out.preceded_by) == "self"
      or first_segment(out.parent_source) == "self"
end

-- Name of the record whose method encloses the cursor, when the expression
-- actually refers to `self`. The walk is skipped otherwise -- it is not free.
local function fill_self_type(out: NodeInfo, parent: ltreesitter.Node, cursor: ltreesitter.Cursor)
   if not references_self(out) then
      return
   end

   -- The node the cursor sits directly under has to be checked before ascending:
   -- under ts-teal a broken method body (`self:` mid-typing) puts the funcname in
   -- the leaf's *immediate* parent, so a walk that moves up first steps over it.
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

-- `self` only becomes a usable type name once the enclosing method is known, so
-- the resolved chain is derived after the self_type walk rather than at build time.
local function fill_resolved_token_chain(out: NodeInfo)
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

local function token_at(cursor: ltreesitter.Cursor, y: integer, x: integer): NodeInfo
   local leaf = descend_to_leaf(cursor, y, x)
   if leaf == nil then
      return nil
   end

   cursor:goto_parent()
   local parent = cursor:current_node()
   local parent_type <const> = parent:type()

   local out: NodeInfo = {
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
      -- Only a name has a token chain. Building one for a "(" or a keyword yields
      -- junk like {"("} -- harmless today because only the identifier path reads it,
      -- but it is a trap for the next reader. Computed before the self_type walk,
      -- which advances the cursor.
      out.token_chain_raw = token_chain_for(leaf, parent)
      fill_hover_position(out, leaf)
   end

   fill_self_type(out, parent, cursor)
   fill_resolved_token_chain(out)

   return out
end


-- Resolve the NodeInfo at (y, x), which are 0-indexed LSP coordinates. The
-- cursor is mutated in place and must already be reset to the tree root; the
-- caller owns its lifetime. Returns nil when the position falls between tokens.
function NodeInfo.from_cursor(cursor: ltreesitter.Cursor, y: integer, x: integer): NodeInfo
   return token_at(cursor, y, x)
end

return NodeInfo
