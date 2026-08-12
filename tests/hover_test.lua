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

-- Declaration-only bodies (any `.d.tl`, including this project's own types/) are
-- where tl's report leaves type references dangling: the checker never resolves
-- an annotation that nothing uses, so the nominal arrives with no `ref` and hover
-- rendered the useless "Cursor: Cursor". A record's own name is worse -- it has no
-- by_pos entry at all, since the RECORD is recorded at the `record` keyword.
local DECL_ONLY_DOC = table.concat({
    "local record ltreesitter",              -- line 0
    "   record Cursor is userdata",          -- line 1
    "      copy: function(Cursor): Cursor",  -- line 2
    "      reset: function(Cursor, Point): FieldId", -- line 3
    "   end",                                -- line 4
    "   interface Point",                    -- line 5
    "      row: integer",                    -- line 6
    "   end",                                -- line 7
    "   type FieldId = integer",             -- line 8
    "end",                                   -- line 9
    "return ltreesitter",                    -- line 10
}, "\n")

local function hover_value(response)
    local contents = response and response.result and response.result.contents
    if contents == nil then return "" end
    local value = type(contents) == "table" and (contents.value or contents[1]) or contents
    return tostring(value)
end

tested.test("hover on a record's own declaration name shows the record", function()
    local uri = "file:///tmp/tls_hover_decl_1.tl"
    client:open_document(uri, DECL_ONLY_DOC)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 1 "   record Cursor is userdata": 'Cursor' starts at col 10
    local value = hover_value(client:get_hover(uri, 1, 10))

    tested.assert({
        given = "hover on the name in 'record Cursor'",
        should = "show the record rather than nothing",
        expected = true,
        actual = value:find("record Cursor", 1, true) ~= nil,
    })
end)

tested.test("hover on an unresolved nominal shows the record, not 'Cursor: Cursor'", function()
    local uri = "file:///tmp/tls_hover_decl_2.tl"
    client:open_document(uri, DECL_ONLY_DOC)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 2 "      copy: function(Cursor): Cursor": return-type 'Cursor' at col 30,
    -- the occurrence tl leaves without a ref
    local value = hover_value(client:get_hover(uri, 2, 30))

    tested.assert({
        given = "hover on a return-type annotation",
        should = "not be the self-referential 'Cursor: Cursor'",
        expected = true,
        actual = value:find("Cursor: Cursor", 1, true) == nil,
    })
    tested.assert({
        given = "hover on a return-type annotation",
        should = "show the record it names",
        expected = true,
        actual = value:find("record Cursor", 1, true) ~= nil,
    })
end)

tested.test("hover on an interface shows 'interface', not 'Point: Point'", function()
    local uri = "file:///tmp/tls_hover_decl_3.tl"
    client:open_document(uri, DECL_ONLY_DOC)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 3 "      reset: function(Cursor, Point): FieldId": 'Point' at col 30
    local value = hover_value(client:get_hover(uri, 3, 30))

    tested.assert({
        given = "hover on an interface-typed annotation",
        should = "render it as an interface",
        expected = true,
        actual = value:find("interface Point", 1, true) ~= nil,
    })
    tested.assert({
        given = "hover on an interface-typed annotation",
        should = "include its fields",
        expected = true,
        actual = value:find("row", 1, true) ~= nil,
    })
end)

-- A type alias is the one kind of declaration that never appears in tr.types under
-- its own name: tl collapses the typedecl into its target, so the entry reads
-- "integer". The name survives only as a key in the enclosing record's fields.
tested.test("hover on a type alias reports the type it stands for", function()
    local uri = "file:///tmp/tls_hover_decl_4.tl"
    client:open_document(uri, DECL_ONLY_DOC)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 3 "      reset: function(Cursor, Point): FieldId": 'FieldId' at col 38
    local at_use = hover_value(client:get_hover(uri, 3, 38))
    tested.assert({
        given = "hover on a use of the alias 'FieldId'",
        should = "resolve to its target type",
        expected = true,
        actual = at_use:find("integer", 1, true) ~= nil,
    })
    tested.assert({
        given = "hover on a use of the alias 'FieldId'",
        should = "not be the self-referential 'FieldId: FieldId'",
        expected = true,
        actual = at_use:find("FieldId: FieldId", 1, true) == nil,
    })

    -- line 8 "   type FieldId = integer": the alias name itself at col 8
    local at_decl = hover_value(client:get_hover(uri, 8, 8))
    tested.assert({
        given = "hover on the alias declaration name",
        should = "resolve to its target type",
        expected = true,
        actual = at_decl:find("integer", 1, true) ~= nil,
    })
end)

return tested
