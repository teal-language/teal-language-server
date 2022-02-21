
local loop <const> = require("tealls.loop")
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

function rpc.decode(): {string:any}, string
   local line = loop.read("*l", false):gsub("\r", "")
   if not line then
      util.log("Failed to read rpc")
      return nil, "eof"
   end

   local len: integer
   while line and line ~= "" do -- parse headers
      local key, val = line:match("^([^:]+): (.+)$")
      if not (key and val) then
         util.log("invalid header")
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
            util.log("invalid Content-Type")
            return nil, string.format(
               "invalid Content-Type: got '%s', expected one of %s",
               val,
               table.concat(map(keys(contenttype), quote), ", ")
            )
         end
      else
         util.log("unexpected header")
         return nil, "unexpected header: " .. line
      end
      line = loop.read("*l", true):gsub("\r", "")
   end

   if not len then
      util.log("Failed to find rpc content")
      return nil, "no Content-Length found"
   end

   local body = loop.read(len, true):gsub("\r", "")
   util.log("   Body: ", body)
   local data = json.decode(body)
   if not data then
      return nil, "Malformed json"
   end
   if data.jsonrpc ~= "2.0" then
      util.log("Incorrect jsonrpc version")
      return nil, "Incorrect jsonrpc version: got " .. tostring(data.jsonrpc) .. " expected 2.0"
   end
   util.log("successfully parsed rpc!")
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

