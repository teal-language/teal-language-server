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

-- On Windows, file:///tmp resolves to the relative path "tmp" (the URI parser
-- strips the leading "/"), which doesn't exist. Use the system temp directory
-- instead, which is guaranteed to exist on any Windows installation.
local function get_root_uri()
    if IS_WINDOWS then
        local temp = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
        return "file:///" .. temp:gsub("\\", "/")
    end
    return "file:///tmp"
end

-- opts.coverage (default true) spawns the server under luacov. Callers that time
-- requests must pass false: luacov's per-line debug hook slows tl.check by ~100x
-- (a check that takes 0.4s takes 42s under it), which reads as a hang from the
-- outside. The test suite leaves it on because it does not time anything.
function LspClient.new(server_binary, opts)
    opts = opts or {}
    local coverage = opts.coverage ~= false

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
    local spawn_args = coverage and { "--coverage" } or {}
    local spawn_env = nil
    if IS_WINDOWS then
        -- Bypass the luarocks-generated .bat wrapper. libuv spawns .bat files
        -- through an internal cmd.exe invocation, and in that chain stdin
        -- never reaches the eventual lua.exe child on Windows runners.
        -- Spawn the current lua.exe with the source script directly and
        -- propagate LUA_PATH/LUA_CPATH so the child resolves modules without
        -- the wrapper.
        spawn_path = uv.exepath()
        spawn_args = { uv.cwd() .. "\\bin\\teal-language-server" }
        if coverage then
            table.insert(spawn_args, "--coverage")
        end

        -- Derive a clean LUA_PATH/LUA_CPATH from the venv structure instead
        -- of using package.path/cpath directly. When running under
        -- "luarocks test", the parent process's package.cpath may include
        -- extra global-luarocks paths (e.g. AppData\Roaming\luarocks\...)
        -- that do not exist but still cause ltreesitter's dynamic-library
        -- loader to segfault on Windows when it iterates them.
        local venv_bin  = uv.exepath():match("^(.*)[\\][^\\]+$")  -- strip lua.exe
        local venv_root = venv_bin and venv_bin:match("^(.*)[\\]bin$") or venv_bin
        -- Use the running Lua version ("5.4", "5.1", etc.) rather than a
        -- hardcoded string so this works under both Lua 5.4 and LuaJIT 2.1
        -- (which self-reports as "Lua 5.1" and installs to lua/5.1/ paths).
        local lua_ver    = _VERSION:match("%d+%.%d+")
        local venv_lib   = (venv_root or "") .. "\\lib\\lua\\" .. lua_ver
        local venv_share = (venv_root or "") .. "\\share\\lua\\" .. lua_ver
        spawn_env = {}
        for k, v in pairs(uv.os_environ()) do
            -- Strip every LUA_PATH/LUA_CPATH variant so our values win.
            if not k:upper():match("^LUA_C?PATH") then
                table.insert(spawn_env, k .. "=" .. v)
            end
        end
        table.insert(spawn_env, "LUA_PATH=" ..
            venv_share .. "\\?.lua;" ..
            venv_share .. "\\?\\init.lua;" ..
            ".\\?.lua")
        table.insert(spawn_env, "LUA_CPATH=" ..
            venv_lib .. "\\?.dll;" ..
            venv_lib .. "\\loadall.dll;" ..
            ".\\?.dll")
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

-- Accessors for out-of-band tooling (scripts/fuzz_snippets.lua,
-- scripts/replay_crasher.lua), whose oracles are "did it die" and "what did it
-- say on the way out" rather than a request/response pair.
function LspClient:get_pid()
    return self._pid
end

-- nil while the server is alive; {code, signal} once it has exited.
function LspClient:exit_info()
    return self._exit_info
end

function LspClient:get_stderr()
    return self._stderr_buffer
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
        local stderr = self._stderr_buffer
        local total = #stderr
        -- Show head + tail when very large so the last-line-before-hang is
        -- visible even if a display layer (markdown, terminal scroll) clips.
        if total > 4000 then
            stderr = stderr:sub(1, 2000)
                .. "\n...[truncated " .. (total - 4000) .. " middle bytes]...\n"
                .. stderr:sub(-2000)
        end
        table.insert(parts, "server stderr (" .. total .. " bytes):\n" .. stderr)
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
        rootUri = root_uri or get_root_uri(),
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

function LspClient:get_type_definition(uri, line, character)
    local id = self:request("textDocument/typeDefinition", {
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
