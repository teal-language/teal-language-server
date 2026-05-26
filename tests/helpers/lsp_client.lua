local uv = require("luv")
local cjson = require("cjson")

local LspClient = {}
LspClient.__index = LspClient

local DEFAULT_TIMEOUT_MS = 15000

-- Lua's package.config first byte is the platform directory separator: "\" on
-- Windows builds of Lua, "/" elsewhere. Set at Lua compile time, so it's a
-- more reliable Windows indicator than uv.os_uname()/os_getenv("OS"), both of
-- which were observed to miss on the MinGW CI runner.
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

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

    local spawn_path = server_binary
    local spawn_verbatim = false
    if IS_WINDOWS then
        -- luarocks installs binaries as ".bat" wrappers on Windows. libuv
        -- (>=1.48) spawns .bat/.cmd files itself with CVE-2024-27980-safe
        -- quoting, so we can target the wrapper directly. An earlier attempt
        -- routed through `cmd.exe /c` instead; that succeeded on MSVC but the
        -- client never received a response — cmd.exe applies CRLF translation
        -- on inherited stdio pipes, which corrupts the `\r\n\r\n` terminator
        -- in LSP `Content-Length` framing. verbatim=true skips libuv's arg
        -- quoting (our only arg has no special chars) which avoids re-escaping
        -- surprises from the batch-file code path.
        spawn_path = server_binary .. ".bat"
        spawn_verbatim = true
    end

    local handle, err_msg, err_name = uv.spawn(spawn_path, {
        args = { "--coverage" },
        stdio = { stdin_pipe, stdout_pipe, nil },
        verbatim = spawn_verbatim,
    }, function() end)
    self._handle = handle

    assert(handle, "failed to spawn server: " .. tostring(spawn_path)
        .. " (" .. tostring(err_msg) .. " / " .. tostring(err_name) .. ")")

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

function LspClient:get_definition(uri, line, character)
    local id = self:request("textDocument/definition", {
        textDocument = { uri = uri },
        position = { line = line, character = character },
    })
    return self:wait_for_response(id)
end

function LspClient:change_document(uri, text, version)
    self:notify("textDocument/didChange", {
        textDocument = { uri = uri, version = version or 2 },
        contentChanges = { { text = text } },
    })
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

    if self._stdin and not uv.is_closing(self._stdin) then
        uv.close(self._stdin)
    end
    if self._stdout and not uv.is_closing(self._stdout) then
        uv.close(self._stdout)
    end
    if self._handle and not uv.is_closing(self._handle) then
        uv.close(self._handle)
    end
end

return LspClient
