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
    local stderr_pipe = uv.new_pipe(false)
    self._stdin = stdin_pipe
    self._stdout = stdout_pipe
    self._stderr = stderr_pipe
    self._stderr_buffer = ""
    self._exit_info = nil

    local spawn_path = server_binary
    local spawn_args = { "--coverage" }
    local spawn_env = nil
    if IS_WINDOWS then
        -- Bypass the luarocks-generated .bat wrapper. libuv spawns .bat files
        -- through an internal cmd.exe invocation, and in that chain stdin
        -- never reached the eventual lua.exe child on the GH Windows runners
        -- (both MinGW and MSVC) — the server stayed alive but silent,
        -- waiting on a stdin that nothing was being written to. Instead,
        -- spawn the current lua.exe with the source script directly. The
        -- script (bin/teal-language-server) is identical to what luarocks
        -- copies into the rocks tree; the wrapper's only added value is
        -- pointing Lua at the rocks tree via `-e "package.path=..."`. We do
        -- the same here by propagating our own package.path/cpath through
        -- LUA_PATH/LUA_CPATH so the child resolves teal_language_server.*
        -- without the wrapper.
        spawn_path = uv.exepath()
        spawn_args = {
            -- Diagnostic: confirm the child's lua.exe is actually running our
            -- code and that its stderr pipe reaches us. If "[startup]" never
            -- appears in captured stderr, the silent failure is upstream of
            -- the Lua script (process inheritance, missing DLL, etc.). If it
            -- does appear, the hang is inside the server's startup.
            "-e", "io.stderr:write('[startup] alive _VERSION='.._VERSION..'\\n'); io.stderr:flush()",
            uv.cwd() .. "\\bin\\teal-language-server",
            "--coverage",
        }

        spawn_env = {}
        for k, v in pairs(uv.os_environ()) do
            -- Skip every LUA_PATH/LUA_CPATH variant (incl. LUA_PATH_5_4) so
            -- our values aren't shadowed by stale ones from the parent env.
            if not k:upper():match("^LUA_C?PATH") then
                table.insert(spawn_env, k .. "=" .. v)
            end
        end
        table.insert(spawn_env, "LUA_PATH=" .. package.path)
        table.insert(spawn_env, "LUA_CPATH=" .. package.cpath)
    end

    local handle, err_msg, err_name = uv.spawn(spawn_path, {
        args = spawn_args,
        stdio = { stdin_pipe, stdout_pipe, stderr_pipe },
        env = spawn_env,
    }, function(code, signal)
        self._exit_info = { code = code, signal = signal }
    end)
    self._handle = handle
    self._pid = handle and uv.process_get_pid(handle) or nil
    self._sends_attempted = 0
    self._write_errors = ""

    assert(handle, "failed to spawn server: " .. tostring(spawn_path)
        .. " (" .. tostring(err_msg) .. " / " .. tostring(err_name) .. ")")

    -- Log spawn details to test runner stderr so CI logs show what we tried
    -- even when the server stays silent.
    io.stderr:write(string.format(
        "[lsp_client] spawned pid=%s path=%s args=[%s]\n",
        tostring(self._pid), tostring(spawn_path),
        table.concat(spawn_args, " | ")))
    io.stderr:flush()

    uv.read_start(stdout_pipe, function(_err, data)
        if data then
            self._buffer = self._buffer .. data
            self:_parse_frames()
        end
    end)

    uv.read_start(stderr_pipe, function(_err, data)
        if data then
            self._stderr_buffer = self._stderr_buffer .. data
        end
    end)

    return self
end

function LspClient:_diagnostics()
    local parts = {}
    if self._pid then
        local alive = pcall(uv.kill, self._pid, 0)
        table.insert(parts, "pid=" .. tostring(self._pid) .. " alive=" .. tostring(alive))
    end
    table.insert(parts, "sends_attempted=" .. tostring(self._sends_attempted or 0))
    if self._write_errors and #self._write_errors > 0 then
        table.insert(parts, "stdin write errors:\n" .. self._write_errors)
    end
    if self._exit_info then
        table.insert(parts, "server exited code=" .. tostring(self._exit_info.code)
            .. " signal=" .. tostring(self._exit_info.signal))
    end
    if self._stderr_buffer and #self._stderr_buffer > 0 then
        table.insert(parts, "server stderr (" .. #self._stderr_buffer .. " bytes):\n" .. self._stderr_buffer)
    else
        table.insert(parts, "server stderr: <empty>")
    end
    if self._buffer and #self._buffer > 0 then
        table.insert(parts, "unparsed stdout buffer (" .. #self._buffer .. " bytes):\n" .. self._buffer)
    else
        table.insert(parts, "server stdout: <empty>")
    end
    return "\n" .. table.concat(parts, "\n")
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
    self._sends_attempted = (self._sends_attempted or 0) + 1
    uv.write(self._stdin, frame, function(err)
        if err then
            self._write_errors = (self._write_errors or "") .. tostring(err) .. "\n"
        end
    end)
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

    assert(not timed_out, "timeout waiting for LSP response id=" .. tostring(id)
        .. self:_diagnostics())

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

    assert(not timed_out, "timeout waiting for LSP notification: " .. tostring(method)
        .. self:_diagnostics())

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
    if self._stderr and not uv.is_closing(self._stderr) then
        uv.close(self._stderr)
    end
    if self._handle and not uv.is_closing(self._handle) then
        uv.close(self._handle)
    end
end

return LspClient
