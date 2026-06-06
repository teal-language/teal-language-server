# TypeReport Lookups

NOTE: this document is AI generated, I had it read through what was already in place and write this up after not having worked on some of the internals for a few months... Do I wish I had written something like this up myself back in late 2024? Yes, yes I do.

## The `tl.TypeReport` structures

After a successful `tl.check` run the type checker populates a `TypeReport` on the shared
environment. Four structures matter for LSP features:

```
TypeReport
  types:          {type_id → TypeInfo}
  globals:        {name → type_id}
  by_pos:         {file → {line → {col → type_id}}}
  symbols_by_file:{file → {Symbol}}   -- Symbol = {y, x, name, type_id}
```

### `types` — type declarations

Maps every type ID to a `TypeInfo` record. The `y`/`x` fields on a `TypeInfo` point to
**where the type itself is declared** (e.g. `record TestType` on line 0, `function` keyword
on line 4). Other useful fields: `str` (display string), `fields` (record field names →
type_id), `args`/`rets` (function parameter/return types), `ref` (nominal indirection).

### `globals` — global name bindings

Maps a global name to its type_id. Use this as a fallback after `symbols_in_scope` fails.

### `by_pos` — position-keyed inverse index

Maps `(file, line, col)` → type_id. Logically the inverse of looking up a type by
position. Currently disabled in `Document:type_information_for_tokens` because it caused
more regressions than it helped (see the commented-out block in `document.tl`). Reserved
for future use.

### `symbols_by_file` — symbol declarations (name bindings)

An **ordered list** of symbol entries per file. Each `Symbol` tuple is `{y, x, name,
type_id}` where `y`/`x` are **where the name was bound** (e.g. `local a` on line 31), not
where its type is declared. Two special pseudo-symbols mark scope boundaries:

| `name` field | Meaning |
|---|---|
| `@{` | scope block opens here |
| `@}` | scope block closes here; `type_id` field holds the list-index of the matching `@{` |

---

## The two fundamental questions

Every LSP feature asks one of two questions about a token:

**"Where is this *type* declared?"** → `TypeInfo.y / TypeInfo.x`

For `local a: TestType`, this leads to `record TestType`. Useful when you want to know the
shape/contract of a value.

**"Where is this *name* bound?"** → a Symbol's `y / x` from `symbols_by_file`

For `local a: TestType`, this leads to `local a`. Useful when you want the declaration of
the variable itself.

These two answers coincide only when a type is declared at the same location it is first
bound — most notably a **local function declaration** (`local function my_func()`).

---

## Resolution utilities

### `tl.symbols_in_scope(tr, y, x, file)` → `{name: type_id}`

Walks `symbols_by_file` **backwards** from `(y, x)`, honoring the `@{`/`@}` scope markers:

- On `@{`: step past it (already inside this scope, keep going outward).
- On `@}`: jump to the matching `@{` index — this skips an entire sibling block that closed
  before the cursor, whose locals are out of scope.
- On a normal symbol: record `name → type_id` only if not already recorded (innermost
  wins, implementing shadowing).

Returns the map of all names visible at the cursor. **Discards positions** — you get
type_ids only, not where the names were declared.

### `Document:type_information_for_tokens(tokens, y, x)` → `TypeInfo`

The main resolution chain used by most LSP features:

1. Calls `symbols_in_scope` to build the in-scope name map.
2. Resolves `tokens[1]` in that map (falls back to `tr.globals`).
3. For each subsequent token, walks `TypeInfo.fields` to follow field accesses.
4. Returns the final `TypeInfo`, whose `y`/`x` point to the **type** declaration.

### `Document:symbol_declaration_position(name, y, x)` → `(y, x)`

Mirrors the `symbols_in_scope` backwards walk but, on a match, returns the matched
Symbol's `y`/`x` — the **declaration site of the name itself**. Used exclusively by
`textDocument/definition` for base symbols.

---

## LSP features: which lookup, and why

| Feature | Lookup used | Why |
|---|---|---|
| `textDocument/hover` | `type_information_for_tokens` → `TypeInfo.str` / `fields` / `args` | Needs the *shape* of the value (type string, field list, function signature) for display. The type's declaration position is not used. |
| `textDocument/completion` | `type_information_for_tokens` → `TypeInfo.fields` / `keys` / `enums` | Needs the set of valid field/method names to offer. For `:` completions, also inspects `TypeInfo.args[1]` to filter to self-methods only. |
| `textDocument/signatureHelp` | `type_information_for_tokens` → `TypeInfo.args` | Needs the parameter names and types of the function being called. |
| `textDocument/typeDefinition` | `type_information_for_tokens` → `TypeInfo.y` / `TypeInfo.x` | Intentionally jumps to the *type* declaration. This is what `textDocument/definition` used to do before the distinction was introduced. |
| `textDocument/definition` (base symbol) | `symbol_declaration_position` → Symbol `y`/`x` | Jumps to where the *name was bound*. `local a: TestType` → `local a`, not `record TestType`. Falls back to `type_information_for_tokens` if the symbol isn't tracked (e.g. a global). |
| `textDocument/definition` (field access) | `type_information_for_tokens` → `TypeInfo.y` / `TypeInfo.x` | The field's `TypeInfo` carries its declaration position for record/function fields, which is correct and works cross-file. Falls back to the *enclosing record's* `TypeInfo` when the field's type has no position (e.g. primitive `boolean`). |

### Summary rule of thumb

- Displaying or completing **what a value is** → `type_information_for_tokens` → `TypeInfo`
- Jumping to **where a type is declared** → `TypeInfo.y` / `TypeInfo.x`
- Jumping to **where a name is declared** → `symbol_declaration_position` → Symbol `y`/`x`
