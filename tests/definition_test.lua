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

-- Name resolution for types declared inside a record must stay anchored to the
-- records that actually enclose the cursor. Searching every record in the file for
-- a member of that name instead cannot tell a nested type from a method, and sends
-- goto-definition on an undeclared `helper` into Thing.helper. Definition and
-- typeDefinition are the paths that expose it: unlike hover, they call
-- type_information_for_tokens directly, with no by_pos lookup in front of it.
tested.test("definition of an undeclared name does not resolve to a same-named record member", function()
    local uri = "file:///tmp/tls_def_undeclared.tl"
    local doc = table.concat({
        "local record Thing",                       -- line 0
        "   helper: function(): string",            -- line 1
        "end",                                      -- line 2
        "local t: Thing = { helper = function(): string return \"\" end }", -- line 3
        "print(t.helper())",                        -- line 4
        "print(helper())",                          -- line 5: undeclared
        "return Thing",                             -- line 6
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 5 "print(helper())": the undeclared 'helper' starts at col 6
    local response = client:get_definition(uri, 5, 6)
    local result = response and response.result
    tested.assert({
        given = "definition of an undeclared identifier sharing a record member's name",
        should = "return no location",
        expected = false,
        actual = type(result) == "table",
    })

    local type_response = client:get_type_definition(uri, 5, 6)
    local type_result = type_response and type_response.result
    tested.assert({
        given = "typeDefinition of an undeclared identifier sharing a record member's name",
        should = "return no location",
        expected = false,
        actual = type(type_result) == "table",
    })
end)

-- The flip side: inside a record body, a bare reference to a type declared in an
-- enclosing record must resolve, since it is neither a scope symbol nor a global.
tested.test("definition of a type declared in an enclosing record resolves", function()
    local uri = "file:///tmp/tls_def_nested_type.tl"
    local doc = table.concat({
        "local record outer",          -- line 0
        "   record Inner",             -- line 1
        "      x: integer",            -- line 2
        "   end",                      -- line 3
        "   type Alias = integer",     -- line 4
        "   f: function(Inner): Alias", -- line 5
        "end",                         -- line 6
        "return outer",                -- line 7
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 5 "   f: function(Inner): Alias": 'Inner' at col 15
    local response = client:get_type_definition(uri, 5, 15)
    local result = response and response.result
    tested.assert({
        given = "typeDefinition of the nested type 'Inner'",
        should = "point to line 1, where Inner is declared",
        expected = 1,
        actual = type(result) == "table" and result.range and result.range.start.line,
    })
end)

return tested
