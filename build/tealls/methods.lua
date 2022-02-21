


local lsp = require("tealls.lsp")
local rpc = require("tealls.rpc")
local util = require("tealls.util")

local methods = {}

function methods.publish_diagnostics(uri, diagnostics, version)
   util.log("publishing diagnostics...")
   rpc.notify("textDocument/publishDiagnostics", {
      uri = uri,
      diagnostics = diagnostics,
      version = version,
   })
end

return methods