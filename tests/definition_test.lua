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

tested.test("definition of locally defined function jumps to its declaration", function()
    local uri = "file:///tmp/tls_def_1.tl"
    local doc = table.concat({
        "local function my_func(): number",
        "  return 42",
        "end",
        "local x = my_func()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 3 "local x = my_func()": 'my_func' starts at col 10
    local response = client:get_definition(uri, 3, 10)

    tested.assert({
        given = "definition response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local result = response.result
    tested.assert({
        given = "definition result",
        should = "have a uri",
        expected = true,
        actual = result ~= nil and result.uri ~= nil,
    })
    tested.assert({
        given = "definition result uri",
        should = "point to the same document",
        expected = true,
        actual = result ~= nil and result.uri == uri,
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 0 (where my_func is declared)",
        expected = 0,
        actual = result ~= nil and result.range ~= nil and result.range.start.line,
    })
end)

tested.test("definition of a locally defined record type jumps to its declaration", function()
    local uri = "file:///tmp/tls_def_2.tl"
    local doc = table.concat({
        "local record Point",
        "  x: number",
        "  y: number",
        "end",
        "local function make(): Point",
        "  return { x = 1, y = 2 }",
        "end",
        "local p = make()",
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 7 "local p = make()": 'make' starts at col 10
    local response = client:get_definition(uri, 7, 10)

    tested.assert({
        given = "local function definition response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local result = response.result
    tested.assert({
        given = "local function definition result",
        should = "have a uri",
        expected = true,
        actual = result ~= nil and result.uri ~= nil,
    })
    tested.assert({
        given = "local function definition result",
        should = "point to line 4 (where make is declared)",
        expected = 4,
        actual = result ~= nil and result.range ~= nil and result.range.start.line,
    })
end)

return tested
