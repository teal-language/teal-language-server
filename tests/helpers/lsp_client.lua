local uv = require("luv")
local cjson = require("cjson")

local LspClient = {}
LspClient.__index = LspClient

local DEFAULT_TIMEOUT_MS = 15000

function LspClient.new(server_binary)
    local self = setmetatable({}, LspClient)
    self._buffer = ""
    self._pending = {}
    self._notifications = {}
    self._next_id = 1

    local stdin_pipe = uv.new_pipe(false)
    local stdout_pipe = uv.new_pipe(false)
    self._stdin = stdin_pipe
    self._stdout = stdout_pipe

    self._handle = uv.spawn(server_binary, {
        args = { "--coverage" },
        stdio = { stdin_pipe, stdout_pipe, nil },
    }, function(_code, _signal)
        self._exited = true
    end)

    assert(self._handle, "failed to spawn server: " .. tostring(server_binary))

    uv.read_start(stdout_pipe, function(_err, data)
        if data then
            self._buffer = self._buffer .. data
            self:_parse_frames()
        end
    end)

    return self
end

function LspClient:_parse_frames()
    while true do
        local header_end = self._buffer:find("\r\n\r\n", 1, true)
        if not header_end then break end

        local header = self._buffer:sub(1, header_end - 1)
        local content_length = tonumber(header:match("Content%-Length: (%d+)"))
        if not content_length then break end

        local body_start = header_end + 4
        local body_end = body_start + content_length - 1
        if #self._buffer < body_end then break end

        local body = self._buffer:sub(body_start, body_end)
        self._buffer = self._buffer:sub(body_end + 1)

        local ok, msg = pcall(cjson.decode, body)
        if ok and type(msg) == "table" then
            if msg.id ~= nil then
                self._pending[msg.id] = msg
            elseif msg.method then
                if not self._notifications[msg.method] then
                    self._notifications[msg.method] = {}
                end
                table.insert(self._notifications[msg.method], msg.params)
            end
        end
    end
end

function LspClient:_send(msg)
    local json = cjson.encode(msg)
    local frame = "Content-Length: " .. #json .. "\r\n\r\n" .. json
    uv.write(self._stdin, frame)
end

function LspClient:request(method, params)
    local id = self._next_id
    self._next_id = self._next_id + 1
    self:_send({ jsonrpc = "2.0", id = id, method = method, params = params or cjson.null })
    return id
end

function LspClient:notify(method, params)
    self:_send({ jsonrpc = "2.0", method = method, params = params or cjson.null })
end

function LspClient:wait_for_response(id, timeout_ms)
    local timed_out = false
    local timer = uv.new_timer()
    uv.timer_start(timer, timeout_ms or DEFAULT_TIMEOUT_MS, 0, function()
        timed_out = true
    end)

    while not self._pending[id] and not timed_out do
        uv.run("once")
    end

    uv.timer_stop(timer)
    uv.close(timer)

    assert(not timed_out, "timeout waiting for LSP response id=" .. tostring(id))

    local response = self._pending[id]
    self._pending[id] = nil
    return response
end

function LspClient:wait_for_notification(method, timeout_ms)
    local timed_out = false
    local timer = uv.new_timer()
    uv.timer_start(timer, timeout_ms or DEFAULT_TIMEOUT_MS, 0, function()
        timed_out = true
    end)

    while not (self._notifications[method] and #self._notifications[method] > 0) and not timed_out do
        uv.run("once")
    end

    uv.timer_stop(timer)
    uv.close(timer)

    assert(not timed_out, "timeout waiting for LSP notification: " .. tostring(method))

    return table.remove(self._notifications[method], 1)
end

function LspClient:initialize(root_uri)
    local id = self:request("initialize", {
        processId = cjson.null,
        rootUri = root_uri or "file:///tmp",
        capabilities = {},
    })
    local response = self:wait_for_response(id)
    self:notify("initialized", {})
    return response
end

function LspClient:open_document(uri, text)
    self:notify("textDocument/didOpen", {
        textDocument = {
            uri = uri,
            languageId = "teal",
            version = 1,
            text = text,
        },
    })
end

-- For completions not triggered by a character (e.g. mid-word like "ma")
-- Omits the context field to bypass the TriggerCharacter guard in misc_handlers.tl:156
function LspClient:get_completions(uri, line, character)
    local id = self:request("textDocument/completion", {
        textDocument = { uri = uri },
        position = { line = line, character = character },
    })
    return self:wait_for_response(id)
end

-- For completions triggered by "." or ":" characters
function LspClient:get_completions_triggered(uri, line, character, trigger_char)
    local id = self:request("textDocument/completion", {
        textDocument = { uri = uri },
        position = { line = line, character = character },
        context = { triggerKind = 2, triggerCharacter = trigger_char },
    })
    return self:wait_for_response(id)
end

function LspClient:get_hover(uri, line, character)
    local id = self:request("textDocument/hover", {
        textDocument = { uri = uri },
        position = { line = line, character = character },
    })
    return self:wait_for_response(id)
end

function LspClient:get_signature_help(uri, line, character)
    local id = self:request("textDocument/signatureHelp", {
        textDocument = { uri = uri },
        position = { line = line, character = character },
    })
    return self:wait_for_response(id)
end

function LspClient:shutdown()
    -- Proper LSP sequence: shutdown request → null response → exit notification
    pcall(function()
        local id = self:request("shutdown", cjson.null)
        self:wait_for_response(id, 5000)
    end)
    pcall(function() self:notify("exit", cjson.null) end)

    -- Wait for the server process to actually exit (up to 2s) so the next
    -- test file starts with a clean uv event loop in single-threaded mode.
    local deadline = uv.now() + 2000
    while not self._exited and uv.now() < deadline do
        uv.run("once")
    end

    if self._stdin and not uv.is_closing(self._stdin) then
        uv.close(self._stdin)
    end
    if self._stdout and not uv.is_closing(self._stdout) then
        uv.read_stop(self._stdout)
        uv.close(self._stdout)
    end
    if self._handle and not uv.is_closing(self._handle) then
        uv.close(self._handle)
    end

    -- Flush any remaining close callbacks so handles are gone before returning.
    uv.run("nowait")
end

return LspClient
