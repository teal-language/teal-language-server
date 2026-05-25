package.path = "./?.lua;" .. package.path

local tested = require("tested")
local LspClient = require("tests.helpers.lsp_client")

local client

tested.before(function()
    client = LspClient.new("teal-language-server")
    client:initialize("file:///tmp")
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

return tested
