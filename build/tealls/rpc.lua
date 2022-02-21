local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local io = _tl_compat and _tl_compat.io or io; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table
local loop = require("tealls.loop")
local lsp = require("tealls.lsp")
local json = require("dkjson")
local util = require("tealls.util")

local rpc = {}

local keys, map, json_nullable =
util.keys, util.map, util.json_nullable

local contenttype = {
   ["application/vscode-jsonrpc; charset=utf8"] = true,
   ["application/vscode-jsonrpc; charset=utf-8"] = true,
}

function rpc.decode()
   local line = loop.read("*l", false):gsub("\r", "")
   if not line then
      util.log("Failed to read rpc")
      return nil, "eof"
   end

   local len
   while line and line ~= "" do
      local key, val = line:match("^([^:]+): (.+)$")
      if not (key and val) then
         util.log("invalid header")
         return nil, "invalid header: " .. line
      end
      util.log("   Header: ", key, " ", val)
      if key == "Content-Length" then
         len = tonumber(val)
      elseif key == "Content-Type" then
         if not contenttype[val] then
            local function quote(s)
               return "'" .. s .. "'"
            end
            util.log("invalid Content-Type")
            return nil, string.format(
            "invalid Content-Type: got '%s', expected one of %s",
            val,
            table.concat(map(keys(contenttype), quote), ", "))

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

function rpc.encode(t)
   assert(t.jsonrpc == "2.0", "jsonrpc ~= 2.0")
   local msg = json.encode(t)
   io.write("Content-Length: ", tostring(#msg), "\r\n\r\n", msg)
   io.flush()
end

function rpc.respond(id, t)
   rpc.encode({
      jsonrpc = "2.0",
      id = json_nullable(id),
      result = t,
   })
end

function rpc.respond_error(id, name, msg, data)
   rpc.encode({
      jsonrpc = "2.0",
      id = json_nullable(id),
      error = {
         code = lsp.error_code[name] or lsp.error_code.UnknownErrorCode,
         message = msg,
         data = data,
      },
   })
end

function rpc.notify(method, params)
   rpc.encode({
      jsonrpc = "2.0",
      method = method,
      params = params,
   })
end

return rpc