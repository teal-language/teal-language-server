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

tested.test("signatureHelp for 'math.sqrt(' returns a signature with parameter types", function()
    local uri = "file:///tmp/tls_signature_1.tl"
    client:open_document(uri, "math.sqrt(")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- col 10 → server subtracts 1 → col 9 = the '(' node; preceded_by = "math.sqrt"
    local response = client:get_signature_help(uri, 0, 10)

    tested.assert({
        given = "signatureHelp response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local sigs = response.result and response.result.signatures or {}
    tested.assert({
        given = "signatureHelp signatures",
        should = "be non-empty",
        expected = true,
        actual = #sigs > 0,
    })
    tested.assert({
        given = "signature label",
        should = "contain 'number' (sqrt's parameter type)",
        expected = true,
        actual = sigs[1] ~= nil and sigs[1].label:find("number") ~= nil,
    })
end)

tested.test("signatureHelp on a chained method call resolves the prior call's return type", function()
    local uri = "file:///tmp/tls_signature_2.tl"
    -- ("hello"):rep(2) returns string, so the second :rep( must resolve through
    -- the first call's return type.
    client:open_document(uri, 'local _ = ("hello"):rep(2):rep(2)')
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- the second '(' is at col 30; cursor at col 31 -> server subtracts 1 -> col 30
    local response = client:get_signature_help(uri, 0, 31)

    tested.assert({
        given = "chained signatureHelp response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local sigs = response.result and response.result.signatures or {}
    tested.assert({
        given = "chained signatureHelp signatures",
        should = "be non-empty",
        expected = true,
        actual = #sigs > 0,
    })
    tested.assert({
        given = "chained signature label",
        should = "contain 'string' (rep's signature)",
        expected = true,
        actual = sigs[1] ~= nil and sigs[1].label:find("string") ~= nil,
    })
end)

tested.test("signatureHelp on a bare local function resolves its parameter types", function()
    local uri = "file:///tmp/tls_signature_3.tl"
    -- the callee is a plain local identifier (not a field access), so bypos_key_for
    -- falls through to the node's own start position.
    local doc = table.concat({
        "local function f(a: number, b: string): number",
        "  return a",
        "end",
        'local _ = f(1, "x")',
    }, "\n")
    client:open_document(uri, doc)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 3 'local _ = f(1, "x")': '(' is at col 11; cursor at col 12 -> subtract 1 -> col 11
    local response = client:get_signature_help(uri, 3, 12)

    tested.assert({
        given = "bare local function signatureHelp response",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local sigs = response.result and response.result.signatures or {}
    tested.assert({
        given = "bare local function signatureHelp signatures",
        should = "be non-empty",
        expected = true,
        actual = #sigs > 0,
    })
    tested.assert({
        given = "bare local function signature label",
        should = "contain 'number' and 'string' (f's parameter types)",
        expected = true,
        actual = sigs[1] ~= nil and sigs[1].label:find("number") ~= nil and sigs[1].label:find("string") ~= nil,
    })
end)

return tested
