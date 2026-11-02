local _module_name = "lsp.reader_writer"

local StdinReader <const> = require("teal_language_server.lsp.stdin_reader")
local lsp <const> = require("teal_language_server.lsp.protocol")
local json <const> = require("cjson")
local uv <const> = require("luv")
local asserts <const> = require("teal_language_server.util.asserts")
local logging <const> = require("teal_language_server.logging")
local class <const> = require("teal_language_server.util.class")

local logger = logging.get_logger(_module_name)

local record LspReaderWriter
   _stdin_reader:StdinReader
   _stdout: uv.Stream
   _disposed: boolean

   metamethod __call: function(self: LspReaderWriter, stdin_reader: StdinReader): LspReaderWriter
end

function LspReaderWriter:__init(stdin_reader: StdinReader)
   asserts.is_not_nil(stdin_reader)
   self._stdin_reader = stdin_reader
   self._disposed = false
end

local record HeaderInfo
   length:integer
   content_type:string
end

local function json_nullable<T>(x: T): T
   if x == nil then
      return json.null as T
   end
   return x
end

local contenttype: {string:boolean} = {
   ["application/vscode-jsonrpc; charset=utf8"] = true,
   ["application/vscode-jsonrpc; charset=utf-8"] = true,
}

function LspReaderWriter:_parse_header(lines:{string}):HeaderInfo
   local len:integer
   local content_type:string

   for _, line in ipairs(lines) do
      local key, val = line:match("^([^:]+): (.+)$")

      asserts.that(key ~= nil and val ~= nil, "invalid header: " .. line)

      logger:trace("Request Header: %s: %s", key, val)

      if key == "Content-Length" then
         asserts.is_nil(len)
         len = tonumber(val) as integer
      elseif key == "Content-Type" then
         if contenttype[val] == nil then
            asserts.fail("Invalid Content-Type '{}'", val)
         end
         asserts.is_nil(content_type)
         content_type = val
      else
         asserts.fail("Unexpected header: {}", line)
      end
   end

   asserts.that(len ~= nil, "Missing Content-Length")

   return {
      length = len,
      content_type = content_type,
   }
end

function LspReaderWriter:initialize()
   local handle_type = uv.guess_handle(1)
   if handle_type == "tty" then
      self._stdout = uv.new_tty(1, false) as uv.Stream
   elseif handle_type == "pipe" or handle_type == "named_pipe" then
      self._stdout = uv.new_pipe(false) as uv.Stream
      assert((self._stdout as uv.Pipe):open(1))
   else

   end
   asserts.that(self._stdout ~= nil)
   logger:trace("Opened pipe for stdout")
end

function LspReaderWriter:dispose()
   asserts.that(not self._disposed)
   self._disposed = true
   self._stdout:close()
   logger:debug("Closed pipe for stdout")
end

function LspReaderWriter:_decode_header():HeaderInfo
   local header_lines:{string} = {}

   logger:trace("Reading LSP rpc header...")
   while true do
      local header_line = self._stdin_reader:read_line()

      if #header_line == 0 then
         break
      end

      table.insert(header_lines, header_line)
   end

   return self:_parse_header(header_lines)
end

function LspReaderWriter:receive_rpc():{string:any}
   local header_info = self:_decode_header()

   logger:trace("Successfully read LSP rpc header: %s\nWaiting to receive body...", header_info)
   local body_line = self._stdin_reader:read(header_info.length)
   logger:trace("Received request Body: %s", body_line)

   local data = json.decode(body_line)

   asserts.that(data and type(data) == 'table', "Malformed json")
   asserts.that(data.jsonrpc == "2.0", "Incorrect jsonrpc version!  Got {} but expected 2.0", data.jsonrpc)

   return data
end

function LspReaderWriter:_encode(t: {string:any})
   assert(t.jsonrpc == "2.0", "Expected jsonrpc to be 2.0")

   local msg = json.encode(t)

   local content = "Content-Length: " .. tostring(#msg) .. "\r\n\r\n" .. msg
   assert(self._stdout:write(content, nil))

   logger:trace("Sending data: %s", content)
end

function LspReaderWriter:send_rpc(id: integer, t: {string:any})
   self:_encode {
      jsonrpc = "2.0",
      id = json_nullable(id),
      result = json_nullable(t),
   }
end

function LspReaderWriter:send_rpc_error(id: integer, name: lsp.ErrorName, msg: string, data: {string:any})
   self:_encode {
      jsonrpc = "2.0",
      id = json_nullable(id),
      error = {
         code = lsp.error_code[name] or lsp.error_code.UnknownErrorCode,
         message = msg,
         data = data,
      },
   }
end

function LspReaderWriter:send_rpc_notification(method: lsp.Method.Name, params: lsp.Method.Params)
   self:_encode {
      jsonrpc = "2.0",
      method = method,
      params = params,
   }
end

class.setup(LspReaderWriter, "LspReaderWriter", {
   nilable_members = { '_stdout' }
})
return LspReaderWriter
