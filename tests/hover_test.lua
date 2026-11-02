package.path = "./?.lua;" .. package.path

local tested = require("tested")
local LspClient = require("tests.helpers.lsp_client")

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

tested.test("hover over 'math.abs' returns type info", function()
    local uri = "file:///tmp/tls_hover_1.tl"
    client:open_document(uri, "math.abs")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- col 5 = start of 'abs'; hover does NOT subtract 1
    local response = client:get_hover(uri, 0, 5)

    tested.assert({
        given = "hover response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    tested.assert({
        given = "hover contents",
        should = "be present",
        expected = true,
        actual = contents ~= nil,
    })
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover value",
        should = "mention 'abs'",
        expected = true,
        actual = tostring(value):find("abs") ~= nil,
    })
end)

-- currently failing, because Teal now sees number=42 and thinks it's an integer
tested.test("hover over a local variable with explicit type annotation returns type info", {expected="FAIL"}, function()
    local uri = "file:///tmp/tls_hover_2.tl"
    local doc = table.concat({
        "local x: number = 42",
        "local _ = x",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 1 "local _ = x": 'x' is at col 10
    local response = client:get_hover(uri, 1, 10)

    tested.assert({
        given = "hover over local variable response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    tested.assert({
        given = "hover over local variable contents",
        should = "be present",
        expected = true,
        actual = contents ~= nil,
    })
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over local variable value",
        should = "mention 'number'",
        expected = true,
        actual = tostring(value):find("number") ~= nil,
    })
end)

tested.test("hover over a record field access returns the field's type", function()
    local uri = "file:///tmp/tls_hover_3.tl"
    local doc = table.concat({
        "local record T",
        "  position: number",
        "end",
        "local t: T",
        "local _ = t.position",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 "local _ = t.position": 'position' starts at col 12; hover does NOT subtract 1
    local response = client:get_hover(uri, 4, 12)

    tested.assert({
        given = "hover over field access response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over field access value",
        should = "mention 'number'",
        expected = true,
        actual = tostring(value):find("number") ~= nil,
    })
end)

tested.test("hover over a colon method name returns the method's function type", function()
    local uri = "file:///tmp/tls_hover_5.tl"
    -- the method identifier is preceded by ':', so by_pos resolves at the ':'
    local doc = table.concat({
        "local record T",
        "  greet: function(self: T): string",
        "end",
        "local t: T",
        "local _ = t:greet()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 "local _ = t:greet()": 'greet' starts at col 12; hover does NOT subtract 1
    local response = client:get_hover(uri, 4, 12)

    tested.assert({
        given = "hover over colon method response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over colon method value",
        should = "mention 'function'",
        expected = true,
        actual = tostring(value):find("function") ~= nil,
    })
end)

tested.test("hover over a bare global function returns type info", function()
    local uri = "file:///tmp/tls_hover_6.tl"
    -- a plain global identifier with no preceding '.'/':' resolves at its own position
    client:open_document(uri, "local _ = print")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 0 "local _ = print": 'print' starts at col 10; hover does NOT subtract 1
    local response = client:get_hover(uri, 0, 10)

    tested.assert({
        given = "hover over bare global response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over bare global value",
        should = "mention 'function'",
        expected = true,
        actual = tostring(value):find("function") ~= nil,
    })
end)

tested.test("hover over 'self' returns the enclosing record type", function()
    local uri = "file:///tmp/tls_hover_7.tl"
    local doc = table.concat({
        "local record T",
        "  x: number",
        "end",
        "function T:m()",
        "  local _ = self",
        "end",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 "  local _ = self": 'self' starts at col 12; hover does NOT subtract 1
    local response = client:get_hover(uri, 4, 12)

    tested.assert({
        given = "hover over self response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over self value",
        should = "mention 'T'",
        expected = true,
        actual = tostring(value):find("T") ~= nil,
    })
end)

tested.test("hover over the middle token of a dotted chain returns that token's type", function()
    local uri = "file:///tmp/tls_hover_8.tl"
    local doc = table.concat({
        "local record Inner",
        "  val: number",
        "end",
        "local record Mid",
        "  inner: Inner",
        "end",
        "local record Outer",
        "  mid: Mid",
        "end",
        "local o: Outer",
        "local _ = o.mid.inner",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 10 "local _ = o.mid.inner": 'mid' starts at col 12; hover does NOT subtract 1
    local response = client:get_hover(uri, 10, 12)

    tested.assert({
        given = "hover over chain middle token response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over chain middle token value",
        should = "mention 'Mid'",
        expected = true,
        actual = tostring(value):find("Mid") ~= nil,
    })
end)

tested.test("hover over a variable initialized from a call returns the call's return type", function()
    local uri = "file:///tmp/tls_hover_4.tl"
    local doc = table.concat({
        "local record Config",
        "  name: string",
        "end",
        "local function getConfig(): Config",
        "  return nil",
        "end",
        "local c = getConfig()",
        "local _ = c",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "local _ = c": 'c' is at col 10; hover does NOT subtract 1
    local response = client:get_hover(uri, 7, 10)

    tested.assert({
        given = "hover over call-initialized variable response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local contents = response.result and response.result.contents
    local value = type(contents) == "table" and (contents.value or contents[1]) or tostring(contents)
    tested.assert({
        given = "hover over call-initialized variable value",
        should = "mention 'Config'",
        expected = true,
        actual = tostring(value):find("Config") ~= nil,
    })
end)

tested.test("hover over a top-level function call named after a defined local function", function()
    local uri = "file:///tmp/tls_hover_topfn.tl"
    local doc = table.concat({
        "local function greet(name: string): string",
        "  return name",
        "end",
        "",
        "local _ = greet(\"bob\")",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 4 "local _ = greet(...)": 'greet' at col 10 (1-based); hover does
    -- not subtract 1
    local response = client:get_hover(uri, 4, 10)

    tested.assert({
        given = "hover over top-level function call response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })
end)

tested.test("hover over a top-level macroexp declaration does not crash", function()
    local uri = "file:///tmp/tls_hover_macroexp_decl.tl"
    local doc = table.concat({
        "local macroexp add(self: SB, line: string): nil",
        "  return nil",
        "end",
        "",
        "local sb: SB = { strings = {} }",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 0 "local macroexp add(...)": 'add' starts at col 16 (1-based); hover
    -- does not subtract 1. The macroexp name's node matches a top-level
    -- statement node without an arg list, so args lookup must degrade
    -- gracefully instead of crashing the handler.
    local response = client:get_hover(uri, 0, 17)

    tested.assert({
        given = "hover over macroexp declaration response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })
end)

tested.test("hover over a macroexp method call does not crash", function()
    local uri = "file:///tmp/tls_hover_macroexp.tl"
    local doc = table.concat({
        "local record SB",
        "  strings: {string}",
        "  add: function(self: SB, line: string): nil = macroexp(self: SB, line: string): nil",
        "    return nil",
        "  end",
        "end",
        "",
        "local sb: SB = { strings = {} }",
        "local _ = sb:add(\"x\")",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 8 "local _ = sb:add(...)": 'add' starts at col 10 (1-based); hover
    -- does not subtract 1
    local response = client:get_hover(uri, 8, 10)

    tested.assert({
        given = "hover over macroexp method response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })
end)

return tested
