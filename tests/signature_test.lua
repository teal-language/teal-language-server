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

return tested
