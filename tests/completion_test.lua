package.path = "./?.lua;" .. package.path

local tested = require("tested")
local LspClient = require("tests.helpers.lsp_client")

local function has_label(items, label)
    for _, item in ipairs(items) do
        if item.label == label then
            return true
        end
    end
    return false
end

local client

tested.before(function()
    client = LspClient.new("teal-language-server")
    client:initialize()
end)

tested.after(function()
    if client then
        client:shutdown()
        client = nil
    end
end)

tested.test("completion for partial identifier 'ma' includes 'math'", function()
    local uri = "file:///tmp/tls_complete_1.tl"
    client:open_document(uri, "ma")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- cursor at col 2 (just after "ma"); server subtracts 1 → col 1 (inside "ma")
    local response = client:get_completions(uri, 0, 2)

    tested.assert({
        given = "completion response for 'ma'",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "completion items for 'ma'",
        should = "include 'math'",
        expected = true,
        actual = has_label(items, "math"),
    })
end)

tested.test("completion for 'math.' includes abs, acos, asin", function()
    local uri = "file:///tmp/tls_complete_2.tl"
    client:open_document(uri, "math.")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- cursor at col 5 (after "math."); server subtracts 1 → col 4 (the '.' node)
    local response = client:get_completions_triggered(uri, 0, 5, ".")

    tested.assert({
        given = "completion response for 'math.'",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "abs", "acos", "asin" }) do
        tested.assert({
            given = "completion items for 'math.'",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("completion for 'table.' includes insert, remove, sort", function()
    local uri = "file:///tmp/tls_complete_3.tl"
    client:open_document(uri, "table.")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- cursor at col 6 (after "table."); server subtracts 1 → col 5 (the '.' node)
    local response = client:get_completions_triggered(uri, 0, 6, ".")

    tested.assert({
        given = "completion response for 'table.'",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "insert", "remove", "sort" }) do
        tested.assert({
            given = "completion items for 'table.'",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion on local string variable returns string methods", function()
    local uri = "file:///tmp/tls_complete_4.tl"
    -- Valid document so tl.check runs and types 's' as string
    client:open_document(uri, "local s = \"hello\"\nlocal _ = s:sub(1, 1)")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 1 "local _ = s:sub(1, 1)": ':' is at col 11; cursor at col 12 → server uses col 11
    local response = client:get_completions_triggered(uri, 1, 12, ":")

    tested.assert({
        given = "colon completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "sub", "rep", "len" }) do
        tested.assert({
            given = "colon completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion on self returns record methods", function()
    local uri = "file:///tmp/tls_complete_5.tl"
    local doc = table.concat({
        "local record Point",
        "  x: number",
        "end",
        "function Point:get_x(): number",
        "  return self.x",
        "end",
        "function Point:do_thing()",
        "  local _ = self:get_x()",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "  local _ = self:get_x()": ':' at col 16; cursor at col 17 → server uses col 16
    local response = client:get_completions_triggered(uri, 7, 17, ":")

    tested.assert({
        given = "self colon completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "self colon completion items",
        should = "include 'get_x'",
        expected = true,
        actual = has_label(items, "get_x"),
    })
end)

tested.test("dot completion three levels deep returns innermost record fields", function()
    local uri = "file:///tmp/tls_complete_6.tl"
    -- Three nested record types; valid document so tl.check types 's' as Scene
    local doc = table.concat({
        "local record Vec3",
        "  x: number",
        "  y: number",
        "  z: number",
        "end",
        "local record Transform",
        "  position: Vec3",
        "  rotation: Vec3",
        "end",
        "local record Scene",
        "  transform: Transform",
        "end",
        "local s: Scene",
        "local _ = s.transform.position.x",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 13 "local _ = s.transform.position.x": third '.' at col 30; cursor at col 31
    -- server subtracts 1 → col 30; preceded_by = "s.transform.position" → Vec3 fields
    local response = client:get_completions_triggered(uri, 13, 31, ".")

    tested.assert({
        given = "3-level deep completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "x", "y", "z" }) do
        tested.assert({
            given = "3-level deep completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("dot completion on enum-keyed table returns enum values", function()
    local uri = "file:///tmp/tls_complete_7.tl"
    local doc = table.concat({
        "local enum Color",
        '  "red"',
        '  "green"',
        '  "blue"',
        "end",
        "local t: {Color:string} = {}",
        'local _ = t.red',
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 6 "local _ = t.red": '.' at col 11; cursor at col 12 → server uses col 11
    local response = client:get_completions_triggered(uri, 6, 12, ".")

    tested.assert({
        given = "enum-keyed table completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "red", "green", "blue" }) do
        tested.assert({
            given = "enum-keyed table completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

-- stock tl skips storing "tuple" typed results in by_pos, so a function call's own
-- position (b:foo()'s "(") has no entry. Instead we look up the *called object*
-- (b:foo, whose function type tl does record) and follow rets[1] to reach Builder.
tested.test("colon completion after a chained method call returns the return type's methods", function()
    local uri = "file:///tmp/tls_complete_8.tl"
    -- Builder-pattern record whose methods return the record itself.
    -- Valid document so tl.check populates by_pos for the chain.
    local doc = table.concat({
        "local record Builder",
        "   foo: function(self: Builder): Builder",
        "   bar: function(self: Builder): Builder",
        "end",
        "local b: Builder",
        "local _ = b:foo():bar()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 5 "local _ = b:foo():bar()": the second ':' (before bar) is at col 17;
    -- cursor at col 18 -> server uses col 17. It is preceded by the call b:foo(),
    -- whose result type (Builder) is resolved via by_pos.
    local response = client:get_completions_triggered(uri, 5, 18, ":")

    tested.assert({
        given = "chained colon completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "foo", "bar" }) do
        tested.assert({
            given = "chained colon completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion on a narrowed variable returns the narrowed type's methods", function()
    local uri = "file:///tmp/tls_complete_9.tl"
    -- 'z' is number|string at declaration but narrowed to string inside the branch.
    -- by_pos reflects the narrowing; the old declared-type walk would not.
    local doc = table.concat({
        "local function f(z: number | string)",
        "   if z is string then",
        "      local _ = z:sub(1, 1)",
        "   end",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 2 "      local _ = z:sub(1, 1)": ':' at col 17; cursor at col 18 -> col 17
    local response = client:get_completions_triggered(uri, 2, 18, ":")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "sub", "rep", "len" }) do
        tested.assert({
            given = "narrowed colon completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

-- same by_pos gap as the chained-call test above: getConfig()'s own "(" position
-- is never recorded, so we resolve via the called object getConfig and rets[1].
tested.test("dot completion on a function call result returns the return record's fields", function()
    local uri = "file:///tmp/tls_complete_10.tl"
    local doc = table.concat({
        "local record Config",
        "  name: string",
        "  port: number",
        "end",
        "local function getConfig(): Config",
        "  return nil",
        "end",
        "local _ = getConfig().name",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "local _ = getConfig().name": '.' at col 21; cursor at col 22 -> col 21
    local response = client:get_completions_triggered(uri, 7, 22, ".")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "name", "port" }) do
        tested.assert({
            given = "call-result dot completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion on a call that returns a string returns string methods", function()
    local uri = "file:///tmp/tls_complete_14.tl"
    -- getName() returns a plain string; following rets[1] reaches the string type,
    -- which the completion handler expands to the string library's methods.
    local doc = table.concat({
        "local function getName(): string",
        '  return "x"',
        "end",
        "local _ = getName():sub(1, 1)",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 3 "local _ = getName():sub(1, 1)": ':' at col 19; cursor at col 20 -> col 19
    local response = client:get_completions_triggered(uri, 3, 20, ":")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "sub", "rep", "len" }) do
        tested.assert({
            given = "call-returns-string colon completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("dot completion on a dot-called function field's result returns the return record's fields", function()
    local uri = "file:///tmp/tls_complete_15.tl"
    -- a.make() calls a *field* function via dot access, so the called object is an
    -- `index` node (not an identifier or method_index); its '.' operator holds
    -- make's function type, whose rets[1] is Config.
    local doc = table.concat({
        "local record Config",
        "  name: string",
        "  port: number",
        "end",
        "local record Api",
        "  make: function(): Config",
        "end",
        "local a: Api",
        "local _ = a.make().name",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 8 "local _ = a.make().name": '.' before name at col 18; cursor at col 19 -> col 18
    local response = client:get_completions_triggered(uri, 8, 19, ".")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "name", "port" }) do
        tested.assert({
            given = "dot-called-field result completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("dot completion continues through field access after a call result", function()
    local uri = "file:///tmp/tls_complete_16.tl"
    -- getConfig().sub is a field access *after* a call; the '.' before sub records
    -- Sub directly (no rets-following needed), so completing '.name' resolves as a
    -- plain by_pos lookup. Guards that chaining past a call keeps working.
    local doc = table.concat({
        "local record Sub",
        "  name: string",
        "  id: number",
        "end",
        "local record Config",
        "  sub: Sub",
        "end",
        "local function getConfig(): Config",
        "  return nil",
        "end",
        "local _ = getConfig().sub.name",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 10 "local _ = getConfig().sub.name": '.' before name at col 25; cursor at col 26 -> col 25
    local response = client:get_completions_triggered(uri, 10, 26, ".")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "name", "id" }) do
        tested.assert({
            given = "field-after-call completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion on a call result filters to the record's methods", function()
    local uri = "file:///tmp/tls_complete_17.tl"
    -- getPoint() returns a record via a plain identifier call; the ':' after it
    -- should list only self-methods (dist, len) and exclude the data field x.
    local doc = table.concat({
        "local record Point",
        "  x: number",
        "  dist: function(self: Point): number",
        "  len: function(self: Point): number",
        "end",
        "local function getPoint(): Point",
        "  return nil",
        "end",
        "local _ = getPoint():dist()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 8 "local _ = getPoint():dist()": ':' at col 20; cursor at col 21 -> col 20
    local response = client:get_completions_triggered(uri, 8, 21, ":")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "dist", "len" }) do
        tested.assert({
            given = "colon-on-call-result completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
    tested.assert({
        given = "colon-on-call-result completion items",
        should = "exclude the data field 'x'",
        expected = false,
        actual = has_label(items, "x"),
    })
end)

tested.test("colon completion on a three-level method chain resolves each call's return type", function()
    local uri = "file:///tmp/tls_complete_18.tl"
    -- b:foo():bar():baz(): completing the third ':' requires following rets through
    -- the second call (b:foo():bar()) back to Builder. Guards chain depth > 2.
    local doc = table.concat({
        "local record Builder",
        "   foo: function(self: Builder): Builder",
        "   bar: function(self: Builder): Builder",
        "   baz: function(self: Builder): Builder",
        "end",
        "local b: Builder",
        "local _ = b:foo():bar():baz()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 6 "local _ = b:foo():bar():baz()": third ':' at col 23; cursor at col 24 -> col 23
    local response = client:get_completions_triggered(uri, 6, 24, ":")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "foo", "bar", "baz" }) do
        tested.assert({
            given = "three-level chain completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

-- Regression: the sibling-scan in Document:_tree_sitter_token used to match a
-- multi-row node purely by row containment, ignoring the column. When a chain
-- spans multiple lines and the next ':' immediately follows the closing ')' on
-- the row where that multi-row node *ends*, the scan wrongly recursed into the
-- already-finished node and returned no NodeInfo. Splitting the chain across
-- lines (as method-chaining style commonly does) was enough to trigger it.
tested.test("colon completion after a multi-line chained call still resolves the return type's methods", function()
    local uri = "file:///tmp/tls_complete_19.tl"
    local doc = table.concat({
        "local record Builder",
        "   foo: function(self: Builder): Builder",
        "   bar: function(self: Builder): Builder",
        "   baz: function(self: Builder): Builder",
        "end",
        "local b: Builder",
        "local _ = b:foo()",
        "   :bar():baz()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 8 "   :bar():baz()" is row 7 (0-indexed). The ':' before baz is at
    -- col 9, right after the ')' that closes ":bar()" -- and ":bar()" itself
    -- belongs to a function_call node spanning rows 6-7. Cursor at col 10 -> col 9.
    local response = client:get_completions_triggered(uri, 7, 10, ":")

    tested.assert({
        given = "multi-line chained colon completion response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "foo", "bar", "baz" }) do
        tested.assert({
            given = "multi-line chained colon completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

-- still failing on stock tl: following rets[1] reaches first's declared return
-- type, a bare unconstrained type variable `T`. tl's report records `T` with no
-- constraint and no fields, so R is not recoverable from the report alone...
tested.test("dot completion on a constrained type parameter returns the constraint's fields", {expected="FAIL"}, function()
    local uri = "file:///tmp/tls_complete_11.tl"
    -- inside the generic body, first(items) has type "T is R" (a type argument);
    -- its result should expose R's fields via the constraint.
    local doc = table.concat({
        "local record R",
        "  val: number",
        "end",
        "local function first<T>(items: {T}): T",
        "  return items[1]",
        "end",
        "local function use<T is R>(items: {T})",
        "  local _ = first(items).val",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "  local _ = first(items).val": '.' at col 24; cursor at col 25 -> col 24
    local response = client:get_completions_triggered(uri, 7, 25, ".")

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "constrained type-parameter dot completion items",
        should = "include 'val'",
        expected = true,
        actual = has_label(items, "val"),
    })
end)

tested.test("dot completion after bracket (map) indexing returns the value type's fields", function()
    local uri = "file:///tmp/tls_complete_12.tl"
    local doc = table.concat({
        "local record Foo",
        "  field: number",
        "  other: string",
        "end",
        "local m: {string: Foo}",
        'local _ = m["hello"].field',
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 5 'local _ = m["hello"].field': '.' at col 20; cursor at col 21 -> col 20
    local response = client:get_completions_triggered(uri, 5, 21, ".")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "field", "other" }) do
        tested.assert({
            given = "bracket-then-dot completion items",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("colon completion after bracket (array) indexing returns the element's methods", function()
    local uri = "file:///tmp/tls_complete_13.tl"
    local doc = table.concat({
        "local record Foo",
        "  go: function(self: Foo): number",
        "end",
        "local a: {Foo}",
        "local _ = a[1]:go()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 'local _ = a[1]:go()': ':' at col 14; cursor at col 15 -> col 14
    local response = client:get_completions_triggered(uri, 4, 15, ":")

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "bracket-then-colon completion items",
        should = "include 'go'",
        expected = true,
        actual = has_label(items, "go"),
    })
end)

tested.test("colon completion includes overloaded (POLY) methods like FILE:read", function()
    local uri = "file:///tmp/tls_complete_19.tl"
    -- io.open returns a FILE whose read/lines methods are overloaded (POLY in the
    -- type report). The ':' self-method filter must still surface them, not just
    -- the single-signature functions (write/close/...).
    local doc = table.concat({
        'local manual_file = io.open("manual.of", "r")',
        'local _ = manual_file:read("l")',
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 1 'local _ = manual_file:read("l")': ':' at col 21; cursor at col 22 -> col 21
    local response = client:get_completions_triggered(uri, 1, 22, ":")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "read", "lines", "write", "close" }) do
        tested.assert({
            given = "colon completion on a FILE",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

tested.test("dot completion on a double (curried) call result returns the innermost return type's fields", function()
    local uri = "file:///tmp/tls_complete_20.tl"
    -- makeInner() returns a function that returns Inner, so makeInner()() is Inner.
    -- bypos_key_for recurses through the nested function_call for the called object,
    -- accumulating a return level per call so the lookup follows rets[1] twice.
    local doc = table.concat({
        "local record Inner",
        "  val: number",
        "end",
        "local function makeInner(): function(): Inner",
        "  return nil",
        "end",
        "local _ = makeInner()().val",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 6 "local _ = makeInner()().val": '.' at col 23; cursor at col 24 -> col 23
    local response = client:get_completions_triggered(uri, 6, 24, ".")

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "double-call dot completion items",
        should = "include 'val'",
        expected = true,
        actual = has_label(items, "val"),
    })
end)

tested.test("dot completion on an overloaded (POLY) function call result returns the return record's fields", function()
    local uri = "file:///tmp/tls_complete_21.tl"
    -- lib.make is overloaded (two signatures -> POLY). follow_rets bails on the
    -- POLY callee, so this must resolve through the token-chain fallback.
    local doc = table.concat({
        "local record Box",
        "  val: number",
        "end",
        "local record lib",
        "  make: function(x: number): Box",
        "  make: function(x: string): Box",
        "end",
        "local _ = lib.make(1).val",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "local _ = lib.make(1).val": '.' at col 21; cursor at col 22 -> col 21
    local response = client:get_completions_triggered(uri, 7, 22, ".")

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "POLY-call-result dot completion items",
        should = "include 'val'",
        expected = true,
        actual = has_label(items, "val"),
    })
end)

-- Known limitation (same root cause as the constrained-type-parameter test above
-- and the note at document.tl:352-357): tl records the generic return as a bare,
-- unconstrained type variable at the callee's position, so follow_rets hits the
-- TYPE_VARIABLE guard and bails, and the token-chain fallback can't resolve a call
-- either. Requires the tl-side fix (PR #74) to resolve.
tested.test("dot completion on a top-level generic call result returns the inferred type's fields", {expected="FAIL"}, function()
    local uri = "file:///tmp/tls_complete_22.tl"
    -- at a top-level call site T is inferred to the concrete element type (Item),
    -- so following rets[1] should reach a real record; today it stays a type var.
    local doc = table.concat({
        "local record Item",
        "  name: string",
        "end",
        "local function first<T>(items: {T}): T",
        "  return items[1]",
        "end",
        "local items: {Item} = {}",
        "local _ = first(items).name",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "local _ = first(items).name": '.' at col 22; cursor at col 23 -> col 22
    local response = client:get_completions_triggered(uri, 7, 23, ".")

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "generic-call-result dot completion items",
        should = "include 'name'",
        expected = true,
        actual = has_label(items, "name"),
    })
end)

-- Typing a trailing '.' on a new last line makes the file unparseable, so the
-- type report still ends at the previous line and the cursor sits past the
-- chunk's closing "@}" marker. The scope walk used to follow that marker's
-- back-pointer over the whole file scope and report nothing in scope, so a local
-- record completed to "(none)" at the one place people reach for completion most.
tested.test("dot completion on a local typed at the end of the file lists its fields", function()
    local uri = "file:///tmp/tls_complete_23.tl"
    local doc_v1 = table.concat({
        "local record tadd",
        "  buffer: {string}",
        "  clear: function()",
        "end",
        "tadd.buffer = {}",
        'print("done")',
    }, "\n")
    client:open_document(uri, doc_v1)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- append "tadd." on a new final line, as an editor would send it mid-typing
    client:change_document(uri, doc_v1 .. "\ntadd.", 2)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 6 "tadd.": '.' at col 4; cursor at col 5 -> col 4
    local response = client:get_completions_triggered(uri, 6, 5, ".")

    local items = response.result and response.result.items or {}
    for _, label in ipairs({ "buffer", "clear" }) do
        tested.assert({
            given = "completion items for a trailing 'tadd.' at end of file",
            should = "include '" .. label .. "'",
            expected = true,
            actual = has_label(items, label),
        })
    end
end)

-- Same clamp, via the in-scope path rather than the field path. This one failed
-- quietly: globals are merged in separately, so the list still looked populated
-- while every local was missing from it.
tested.test("partial identifier completion at the end of the file still sees locals", function()
    local uri = "file:///tmp/tls_complete_24.tl"
    local doc_v1 = table.concat({
        "local record tadd",
        "  buffer: {string}",
        "end",
        'print("done")',
    }, "\n")
    client:open_document(uri, doc_v1)
    client:wait_for_notification("textDocument/publishDiagnostics")

    client:change_document(uri, doc_v1 .. "\ntad", 2)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 "tad": cursor at col 3 -> col 2, inside the identifier
    local response = client:get_completions(uri, 4, 3)

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "in-scope completion items on a new last line",
        should = "include the local 'tadd'",
        expected = true,
        actual = has_label(items, "tadd"),
    })
    tested.assert({
        given = "in-scope completion items on a new last line",
        should = "still include globals like 'math'",
        expected = true,
        actual = has_label(items, "math"),
    })
end)

tested.test("identifier completion on a parameter name being declared returns nothing", function()
    local uri = "file:///tmp/tls_complete_26.tl"
    local doc = table.concat({
        "local existing_var = 1",
        "local function f(existin: number)",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 1 "local function f(existin: number)": cursor at col 24 (end of "existin") -> col 23
    local response = client:get_completions(uri, 1, 24)

    -- cjson decodes a JSON null result as the userdata cjson.null, not Lua nil.
    tested.assert({
        given = "completion response for a parameter name being declared",
        should = "have no result",
        expected = true,
        actual = response == nil or type(response.result) ~= "table",
    })
end)

tested.test("identifier completion on a record field name being declared returns nothing", function()
    local uri = "file:///tmp/tls_complete_27.tl"
    local doc = table.concat({
        "local existing_field = 1",
        "local record R",
        "  existin: number",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 2 "  existin: number": cursor at col 9 (end of "existin") -> col 8
    local response = client:get_completions(uri, 2, 9)

    tested.assert({
        given = "completion response for a record field name being declared",
        should = "have no result",
        expected = true,
        actual = response == nil or type(response.result) ~= "table",
    })
end)

return tested
