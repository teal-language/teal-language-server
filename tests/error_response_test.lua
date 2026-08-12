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

-- Every request carries an id and is owed exactly one response. When the server
-- had nothing to say -- no handler registered, or a handler that raised -- it used
-- to only log and return, leaving the client waiting forever. These assert that a
-- failure comes back as a JSON-RPC error rather than as silence; a regression here
-- shows up as the request timing out.
local function send_and_wait(method, params)
    local id = client:request(method, params)
    local ok, message = pcall(function()
        return client:wait_for_response(id, 8000)
    end)
    return ok and message or nil
end

tested.test("a request for an unhandled method answers with MethodNotFound", function()
    local message = send_and_wait("$/notARealMethod", {})

    tested.assert({
        given = "a request for a method the server has no handler for",
        should = "get a response at all, rather than hanging",
        expected = true,
        actual = message ~= nil,
    })
    tested.assert({
        given = "the response to an unhandled method",
        should = "be JSON-RPC error -32601 (MethodNotFound)",
        expected = -32601,
        actual = message and message.error and message.error.code,
    })
end)

tested.test("a request whose handler raises answers with InternalError", function()
    -- no textDocument at all: the hover handler cannot get a document out of this
    -- and raises while resolving it
    local message = send_and_wait("textDocument/hover", {
        position = { line = 0, character = 0 },
    })

    tested.assert({
        given = "a request whose handler raises",
        should = "get a response at all, rather than hanging",
        expected = true,
        actual = message ~= nil,
    })
    tested.assert({
        given = "the response to a request whose handler raised",
        should = "be JSON-RPC error -32603 (InternalError)",
        expected = -32603,
        actual = message and message.error and message.error.code,
    })
end)

tested.test("the server keeps serving requests after a handler raises", function()
    send_and_wait("textDocument/hover", { position = { line = 0, character = 0 } })

    local uri = "file:///tmp/tls_after_error.tl"
    client:open_document(uri, "local x = 1")
    client:wait_for_notification("textDocument/publishDiagnostics")

    -- line 0 "local x = 1": 'x' at col 6
    local message = send_and_wait("textDocument/hover", {
        textDocument = { uri = uri },
        position = { line = 0, character = 6 },
    })

    tested.assert({
        given = "a well-formed request following one that raised",
        should = "still be answered, i.e. the read loop survived",
        expected = true,
        actual = message ~= nil and message.result ~= nil,
    })
end)

return tested
