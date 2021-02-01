
local assert = require("luassert")
local rpc = require("tealls.rpc")

local function fake_fd(str)
   local idx = 1
   return {
      read = function(_self, desc)
         if type(desc) == "number" then
            local substr = str:sub(idx, idx + desc - 1)
            idx = idx + desc
            return substr
         elseif desc == "*l" or desc == "l" then
            local next_idx = str:find("\n", idx)
            local substr = str:sub(idx, next_idx - 1)
            idx = next_idx + 1
            return substr
         else
            error("unimplemented " .. tostring(desc))
         end
      end,
   }
end

-- concat with \r\n
local function lines(tab)
   return table.concat(tab, "\r\n")
end

local function mock_rpc_message(content)
   return fake_fd(lines{
      ("Content-Length: %d"):format(#content),
      "Content-Type: application/vscode-jsonrpc; charset=utf8",
      "",
      content,
   })
end

local function decode(content)
   return rpc.decode(mock_rpc_message(content))
end

describe("rpc", function()
   it("should decode the minimal possible message", function()
      local data, err = decode[[{"jsonrpc":"2.0"}]]
      assert(not err)
      assert(data.jsonrpc == "2.0")
   end)

   it("should report when jsonrpc is the incorrect version", function()
      local data, err = decode[[{"jsonrpc":"1.2"}]]
      assert(not data)
      assert.match("Incorrect jsonrpc", err)
   end)

   it("should report unexpected headers", function()
      local fd = fake_fd(lines{
         "Content-Length: 17",
         "This-Shouldnt-Be-Here: 'hi :D'",
         "",
         [[{"jsonrpc":"2.0"}]],
      })
      local data, err = rpc.decode(fd)
      assert(not data)
      assert.match("unexpected header: ", err)
   end)

   it("should report malformed json data", function()
      local data, err = decode[[{"jsonrpc  abcde}]]
      assert(not data)
      assert.match("Malformed json", err)
   end)
end)

