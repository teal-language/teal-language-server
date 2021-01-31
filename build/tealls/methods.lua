
local lsp = require("tealls.lsp")
local rpc = require("tealls.rpc")

local methods = {}

function methods.publish_diagnostics(uri, diagnostics, version)
   rpc.notify("textDocument/publishDiagnostics", {
      uri = uri,
      diagnostics = diagnostics,
      version = version,
   })
end

return methods
