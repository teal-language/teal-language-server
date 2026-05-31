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

tested.test("didChange updates document so completions reflect new content", function()
    local uri = "file:///tmp/tls_change_1.tl"

    -- Open with a document that has a record with field 'alpha'
    local doc_v1 = table.concat({
        "local record MyRec",
        "  alpha: number",
        "end",
        "local r: MyRec",
        "local _ = r.alpha",
    }, "\n")
    client:open_document(uri, doc_v1)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- Now change the document so the record has fields 'beta' and 'gamma'
    local doc_v2 = table.concat({
        "local record MyRec",
        "  beta: number",
        "  gamma: string",
        "end",
        "local r: MyRec",
        "local _ = r.beta",
    }, "\n")
    client:change_document(uri, doc_v2, 2)
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 5 "local _ = r.beta": '.' at col 11; cursor at col 12
    local response = client:get_completions_triggered(uri, 5, 12, ".")

    tested.assert({
        given = "completions after didChange",
        should = "have a result",
        expected = true,
        actual = response ~= nil and response.result ~= nil,
    })

    local items = response.result and response.result.items or {}
    tested.assert({
        given = "completions after didChange",
        should = "include 'beta' from updated document",
        expected = true,
        actual = has_label(items, "beta"),
    })
    tested.assert({
        given = "completions after didChange",
        should = "include 'gamma' from updated document",
        expected = true,
        actual = has_label(items, "gamma"),
    })
end)

return tested
