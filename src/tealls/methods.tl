
local lsp <const> = require("tealls.lsp")
local rpc <const> = require("tealls.rpc")

local methods <const> = {}

function methods.publish_diagnostics(uri: string, diagnostics: {lsp.Diagnostic}, version: number)
   rpc.notify("textDocument/publishDiagnostics", {
      uri = uri,
      diagnostics = diagnostics,
      version = version,
   } as lsp.Method.Params)
end

return methods
