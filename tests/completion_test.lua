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

return tested
