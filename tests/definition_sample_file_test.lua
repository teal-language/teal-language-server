package.path = "./?.lua;" .. package.path

local tested = require("tested")
local LspClient = require("tests.helpers.lsp_client")

-- Document mirrors test/sample-file.tl exactly.
-- Line numbers below are 0-indexed (LSP convention).
--
-- Line  0: local record TestType
-- Line  1:   test_value: boolean
-- Line  2: (blank)
-- Line  3:   metamethod __call: function(self: TestType): boolean
-- Line  4: end
-- Line  5: (blank)
-- Line  6: local TestType_mt: metatable<TestType>
-- Lines 7-10: block comment
-- Line 11: TestType_mt = {
-- Line 12:   __call = function(self: TestType): boolean
-- Lines 13-19: block comment
-- Line 20:     return self.test_value
-- Lines 21-22: end / }
-- Line 23: (blank)
-- Lines 24-30: block comment
-- Line 31: local a: TestType = setmetatable({test_value = true}, TestType_mt)
-- Line 32: (blank)
-- Lines 33-36: block comment
-- Line 37: a()
local doc = [=[
local record TestType
  test_value: boolean

  metamethod __call: function(self: TestType): boolean
end

local TestType_mt: metatable<TestType>
--[[
  trying textDocument/definition on `TestType_mt` attempts to go to the definition for `metatable` in stdlib.d.tl
  - should always go to `local TestType_mt`
]]
TestType_mt = {
  __call = function(self: TestType): boolean
    --[[
      trying textDocument/definition on `self` fails (No LSP Definitions found)
      - should go to `self` in the function parameters

      trying textDocument/definition on `test_value` fails (No LSP Definitions found)
      - should go to `test_value` within `local record TestType`
    ]]
    return self.test_value
  end
}

--[[
  trying textDocument/definition on `a` goes to `local record TestType`
  - should go to itself as this is the definition

  trying textDocument/definition on `test_value` fails (No LSP Definitions found)
  - should either go to itself or to `test_value` within `local record TestType`
]]
local a: TestType = setmetatable({test_value = true}, TestType_mt)

--[[
  trying textDocument/definition on `a` goes to `local record TestType`
  - should probably go to __call in the metatable, but could also reasonably go to `local a`
]]
a()
]=]

-- NOTE: Lua already drops the single newline immediately following the [=[
-- opening long bracket, so `doc` starts at "local record TestType". Do NOT
-- sub(2) here: that would strip the leading "l" of "local" and turn the whole
-- document into a parse error, which silently disables type checking (and made
-- every definition request below return null).

local cjson = require("cjson")

-- cjson decodes a JSON null as the userdata cjson.null, not Lua nil.
-- Use this helper everywhere we guard against "no result".
local function is_table(v)
    return type(v) == "table"
end

local client
local uri = "file:///tmp/tls_def_sample_file.tl"

tested.before(function()
    client = LspClient.new("teal-language-server")
    client:initialize()
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")
end)

tested.after(function()
    if client then
        client:shutdown()
        client = nil
    end
end)

-- Line 11: "TestType_mt = {", TestType_mt at col 0.
-- Previously jumped to `metatable` in stdlib.d.tl (the type); now goes to the
-- symbol declaration `local TestType_mt` on line 6.
tested.test("definition of TestType_mt from usage site jumps to its local declaration", function()
    local response = client:get_definition(uri, 11, 0)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "point to the same document (not stdlib)",
        expected = uri,
        actual = is_table(result) and result.uri,
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 6 (where local TestType_mt is declared)",
        expected = 6,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 20: "    return self.test_value", self at col 11.
-- Previously returned no result because self_type is nil for function literals (not named
-- methods), causing split_by_symbols to insert nil as the first token. Now `self` is kept
-- literal and resolved as an in-scope parameter symbol.
tested.test("definition of self inside a function literal jumps to its parameter declaration", function()
    local response = client:get_definition(uri, 20, 11)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 12 (where self: TestType is declared as a parameter)",
        expected = 12,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 20: "    return self.test_value", test_value at col 16.
-- The nil-token issue is fixed (self is kept literal), so the field access now resolves.
-- tl's type report does not expose record-field positions, and `test_value`'s type
-- (boolean) is a primitive with no position, so we fall back to the enclosing record's
-- declaration (line 0, `local record TestType`) rather than the exact field on line 1.
tested.test("definition of field access test_value in self.test_value jumps to its enclosing record", function()
    local response = client:get_definition(uri, 20, 16)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 0 (the enclosing record TestType declaration)",
        expected = 0,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 31: "local a: TestType = setmetatable(...)", a at col 6 (the declaration itself).
-- Previously jumped to `local record TestType` (the type, line 0); now resolves to the
-- symbol declaration, which is `a` itself on line 31.
tested.test("definition of a at its own declaration jumps to itself", function()
    local response = client:get_definition(uri, 31, 6)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 31 (the declaration itself)",
        expected = 31,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 31: "local a: TestType = setmetatable({test_value = true}, ...)", test_value at col 34.
-- Known limitation: table-literal keys are not tracked as symbols by tl, and the table's
-- target type is not readily available at this node, so no result is returned. Ideally this
-- would jump to `test_value: boolean` in TestType (line 1). Kept as an expected failure.
tested.test("definition of test_value key in table literal jumps to its record field declaration", {expected="FAIL"}, function()
    local response = client:get_definition(uri, 31, 34)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 1 (where test_value: boolean is declared in TestType)",
        expected = 1,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 37: "a()", a at col 0 (the call site).
-- Previously jumped to `local record TestType` (the type, line 0); now resolves to the
-- symbol declaration `local a` on line 31.
tested.test("definition of a at a call site jumps to its local declaration", function()
    local response = client:get_definition(uri, 37, 0)
    local result = response and response.result

    tested.assert({
        given = "definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "definition result range",
        should = "point to line 31 (where local a is declared)",
        expected = 31,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- textDocument/typeDefinition keeps the *type*-resolving behavior that
-- textDocument/definition used to have.

-- Line 37: "a()", a at col 0. typeDefinition resolves the type of `a` (TestType)
-- and jumps to where that record is declared (line 0).
tested.test("type definition of a jumps to its record type declaration", function()
    local response = client:get_type_definition(uri, 37, 0)
    local result = response and response.result

    tested.assert({
        given = "type definition result",
        should = "point to the same document",
        expected = uri,
        actual = is_table(result) and result.uri,
    })
    tested.assert({
        given = "type definition result range",
        should = "point to line 0 (where record TestType is declared)",
        expected = 0,
        actual = is_table(result) and is_table(result.range) and result.range.start.line,
    })
end)

-- Line 11: "TestType_mt = {", TestType_mt at col 0. typeDefinition resolves the
-- type `metatable<TestType>` and jumps into the stdlib definition (a different file).
tested.test("type definition of TestType_mt jumps to the metatable type in stdlib", function()
    local response = client:get_type_definition(uri, 11, 0)
    local result = response and response.result

    tested.assert({
        given = "type definition result",
        should = "have a result",
        expected = true,
        actual = is_table(result),
    })
    tested.assert({
        given = "type definition result uri",
        should = "point to a different file (the stdlib, not the open document)",
        expected = false,
        actual = is_table(result) and (result.uri == uri),
    })
end)

return tested
