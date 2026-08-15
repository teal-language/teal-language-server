local _module_name = "analysis.node_info"

-- The grammar boundary. Everything that knows a tree-sitter node type name lives
-- in this module -- this file and the `node_info/` folder beside it; nothing
-- outside it should compare against one. Handlers read the normalized `kind` and
-- the flags below instead, so swapping the grammar is a change to this module
-- rather than to every handler.
--
-- This file owns the shape handlers see and the per-kind dispatch that fills it.
-- The work each branch delegates to lives next door, split by what it is about:
--   node_info/tree_walk.tl       cursor/node primitives
--   node_info/token_chain.tl     node -> the chain of names it denotes
--   node_info/bypos_key.tl       node -> where tl records its type; callee lookup
--   node_info/self_resolution.tl `self` -> the enclosing record's name

local ltreesitter <const> = require("ltreesitter")

local tree_walk <const> = require("teal_language_server.analysis.node_info.tree_walk")
local token_chain <const> = require("teal_language_server.analysis.node_info.token_chain")
local bypos_key <const> = require("teal_language_server.analysis.node_info.bypos_key")
local self_resolution <const> = require("teal_language_server.analysis.node_info.self_resolution")

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
   -- Source range of the token itself, in LSP's own coordinates: 0-indexed and
   -- half-open, [start_x, end_x) on start_y. Handlers report this rather than
   -- the requested position, which is only ever *somewhere inside* the token.
   start_y: integer
   start_x: integer
   end_y: integer
   end_x: integer
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
   name_at_cursor: function(ltreesitter.Cursor, integer, integer): NodeInfo
   enclosing_records: function(ltreesitter.Cursor, integer, integer): {string}
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
      out.bypos_y, out.bypos_x, out.bypos_ret_depth = bypos_key.for_node(prev)
   end
end

-- Signature help: resolve what is being called.
local function fill_signature_trigger(out: NodeInfo, leaf: ltreesitter.Node, parent: ltreesitter.Node, cursor: ltreesitter.Cursor)
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

-- The *name* of a parameter in a function type -- the `self` and the `name` of
-- `function(self: Parser, name: string)`. Unlike a real parameter (a `parname`,
-- which tl does record) this name declares nothing at all: there is no symbol
-- for it and no by_pos entry, only a type recorded at the annotation beside it.
--
-- Left on the ordinary identifier path both lookups miss and the token-chain
-- fallback resolves the bare name against the enclosing record, so hovering the
-- `name` parameter of `name: function(self: Parser, name: string)` answered with
-- the *field* `name` -- the whole function -- and hovering `self` answered with
-- nothing. Both are therefore pointed at the annotation instead.
local function fill_partype_name(out: NodeInfo, leaf: ltreesitter.Node, annotation: ltreesitter.Node)
   local start_point = annotation:start_point()
   out.bypos_y = start_point.row + 1
   out.bypos_x = start_point.column + 1
   -- The chain carries the annotation's own name so a ref-less nominal -- the norm
   -- in a .d.tl, where by_pos gives up -- still reaches the type-declaration
   -- fallback. A structural annotation names nothing to chase, but by_pos always
   -- answers for those, so the name is left in place as an inert last resort.
   out.token_chain_raw = token_chain.for_nominal(annotation) or { leaf:source() }
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

local function token_at(cursor: ltreesitter.Cursor, y: integer, x: integer): NodeInfo
   local leaf = tree_walk.descend_to_leaf(cursor, y, x)
   if leaf == nil then
      return nil
   end

   local leaf_start <const> = leaf:start_point()
   local leaf_end <const> = leaf:end_point()

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
      -- A `partype`'s only identifier child is its parameter name; the annotation
      -- beside it is wrapped in a `type`, so this cannot fire on the type itself.
      local annotation: ltreesitter.Node
      if parent_type == "partype" then
         annotation = parent:child_by_field_name("type")
      end

      if annotation ~= nil then
         fill_partype_name(out, leaf, annotation)
      else
         -- Only a name has a token chain. Building one for a "(" or a keyword yields
         -- junk like {"("} -- harmless today because only the identifier path reads it,
         -- but it is a trap for the next reader. Computed before the self_type walk,
         -- which advances the cursor.
         out.token_chain_raw = token_chain.for_leaf(leaf, parent)
         fill_hover_position(out, leaf)
      end
   end

   -- Gated on the cheap text test because the walk up to the enclosing method is
   -- not free, and it advances the cursor -- so nothing below may read from it.
   if self_resolution.references_self(out.token_chain_raw, out.preceded_by, out.parent_source) then
      out.self_type = self_resolution.enclosing_receiver(parent, cursor)
   end
   out.token_chain = self_resolution.resolve_chain(out.token_chain_raw, out.self_type)

   return out
end


-- Resolve the NodeInfo at (y, x), which are 0-indexed LSP coordinates. The
-- cursor is mutated in place and must already be reset to the tree root; the
-- caller owns its lifetime. Returns nil when the position falls between tokens.
function NodeInfo.from_cursor(cursor: ltreesitter.Cursor, y: integer, x: integer): NodeInfo
   return token_at(cursor, y, x)
end

-- The *name* at (y, x), for the requests that ask "what is this thing called":
-- hover, goto-definition, goto-type-definition.
--
-- Editors resolve a mouse position to the nearest character *boundary*, not to
-- the character itself -- Sublime's LSP client does, and it is the reason this
-- exists -- so pointing at the right half of a letter reports the column after
-- it. tree-sitter end points are exclusive, so on the last letter of a name that
-- column is already outside it: on the ":" of `a: string`, or between tokens
-- entirely when a space follows. Every name was therefore dead over its final
-- letter, and a one-letter parameter -- whose only other half is its first --
-- effectively dead everywhere.
--
-- Retrying one column back is sound precisely *because* the first lookup did not
-- find a name: had the name extended past x, x would have landed inside it and
-- the first lookup would have returned it. Only a name ending exactly at x can
-- turn up here, so this cannot reach past an adjacent token.
--
-- Completion and signature help deliberately aim at a punctuation trigger and
-- must not slide off it onto the name before it; they keep from_cursor.
function NodeInfo.name_at_cursor(cursor: ltreesitter.Cursor, y: integer, x: integer): NodeInfo
   -- the caller's contract is that the cursor starts at the root, so this is it;
   -- token_at moves the cursor, and the retry has to start over from the top
   local root <const> = cursor:current_node()

   local out <const> = token_at(cursor, y, x)
   if x == 0 or (out ~= nil and out.kind == "identifier") then
      return out
   end

   cursor:reset(root)
   local before <const> = token_at(cursor, y, x - 1)
   if before ~= nil and before.kind == "identifier" then
      return before
   end
   return out
end

-- Names of the record and interface declarations enclosing (y, x), outermost
-- first -- {"ltreesitter", "Cursor"} for a cursor inside `record Cursor` inside
-- `record ltreesitter`.
--
-- This is how a type declared inside a record is named at all. Only the outermost
-- of these is a scope symbol; everything nested is reachable only as a field of
-- it, so the list doubles as the prefix that turns a bare `FieldId` into the
-- resolvable chain {"ltreesitter", "FieldId"}. Deriving the prefix from the tree
-- is what keeps it exact -- the alternative, searching every record in the file
-- for a member of that name, cannot distinguish a nested type from a method.
--
-- The name of a `recordbody` hangs off its parent: a `stat` for a top-level
-- `local record R`, a `recordentry` for a nested one, and in both cases it is
-- that parent's first `identifier` child. Interfaces differ only in the keyword.
-- Same cursor contract as from_cursor: reset to the root, mutated in place.
function NodeInfo.enclosing_records(cursor: ltreesitter.Cursor, y: integer, x: integer): {string}
   local names: {string} = {}
   if tree_walk.descend_to_leaf(cursor, y, x) == nil then
      return names
   end

   while cursor:goto_parent() do
      if cursor:current_node():type() == "recordbody" then
         -- step onto the declaration itself to read its name
         if not cursor:goto_parent() then
            break
         end
         local name: string
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
