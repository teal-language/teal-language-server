
-- Methods that the server requests of the client

local lsp <const> = require("tealls.lsp")
local rpc <const> = require("tealls.rpc")
local util <const> = require("tealls.util")

local methods <const> = {}

function methods.publish_diagnostics(uri: string, diagnostics: {lsp.Diagnostic}, version: number)
   util.log("publishing diagnostics: ", diagnostics)
   rpc.notify("textDocument/publishDiagnostics", {
      uri = uri,
      diagnostics = diagnostics,
      version = version,
   } as lsp.Method.Params)
end

return methods
