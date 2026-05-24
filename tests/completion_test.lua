-- Add project root to module search path so helpers are findable
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
    client:initialize("file:///tmp")
end)

tested.after(function()
    if client then
        client:shutdown()
        client = nil
    end
end)

tested.test("completion for partial identifier 'ma' includes 'math'", function()
    local uri = "file:///tmp/tls_test_1.tl"
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
    local uri = "file:///tmp/tls_test_2.tl"
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

return tested
