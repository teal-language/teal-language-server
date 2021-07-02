
local lsp <const> = require("tealls.lsp")
local json <const> = require("dkjson")
local util <const> = require("tealls.util")

local rpc <const> = {}

local keys <const>, map <const>, json_nullable <const>
   = util.keys, util.map, util.json_nullable

local contenttype: {string:boolean} = {
   ["application/vscode-jsonrpc; charset=utf8"] = true,
   ["application/vscode-jsonrpc; charset=utf-8"] = true,
}

--[[
   TODO: look into non-blocking io
     - luasocket: popular module, language servers can communicate over sockets instead of stdio, portable
     - luv: no typedefs until interfaces (or whatever), maybe a little big? cross-platform
     - cqueues: nice to use with coroutines, unix only
]]

local function read_line(fh: FILE): string
   local line = fh:read("*l")
   if not line then return end
   line = line:gsub("\r", "")
   return line
end

function rpc.decode(fh: FILE): {string:any}, string
   fh = fh or io.stdin
   util.log("Decoding rpc (doing blocking read)")
   local line = read_line(fh)
   if not line then
      return nil, "eof"
   end

   local len: integer
   while line and line ~= "" do -- parse headers
      local key, val = line:match("^([^:]+): (.+)$")
      if not (key and val) then
         return nil, "invalid header: " .. line
      end
      util.log("   Header: ", key, " ", val)
      if key == "Content-Length" then
         len = tonumber(val) as integer
      elseif key == "Content-Type" then
         if not contenttype[val] then
            local function quote(s: string): string
               return "'" .. s .. "'"
            end
            return nil, string.format(
               "invalid Content-Type: got '%s', expected one of %s",
               val,
               table.concat(map(keys(contenttype), quote), ", ")
            )
         end
      else
         return nil, "unexpected header: " .. line
      end
      line = read_line(fh)
   end

   if not len then
      return nil, "no Content-Length found"
   end

   local body = fh:read(len)
   body = body:gsub("\r", "")
   util.log("   Body: ", body)
   local data = json.decode(body)
   if not data then
      return nil, "Malformed json"
   end
   if data.jsonrpc ~= "2.0" then
      return nil, "Incorrect jsonrpc version: got " .. tostring(data.jsonrpc) .. " expected 2.0"
   end
   return data
end

function rpc.encode(t: {string:any})
   assert(t.jsonrpc == "2.0", "jsonrpc ~= 2.0")
   local msg = json.encode(t)
   io.write("Content-Length: ", tostring(#msg), "\r\n\r\n", msg)
   io.flush()
end

function rpc.respond(id: integer, t: {string:any})
   rpc.encode{
      jsonrpc = "2.0",
      id = json_nullable(id),
      result = t,
   }
end

function rpc.respond_error(id: integer, name: lsp.ErrorName, msg: string, data: {string:any})
   rpc.encode{
      jsonrpc = "2.0",
      id = json_nullable(id),
      error = {
         code = lsp.error_code[name] or lsp.error_code.UnknownErrorCode,
         message = msg,
         data = data,
      },
   }
end

function rpc.notify(method: lsp.Method.Name, params: lsp.Method.Params)
   rpc.encode{
      jsonrpc = "2.0",
      method = method,
      params = params,
   }
end

return rpc

