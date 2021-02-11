




local lsp = {Message = {ResponseError = {}, }, Position = {}, Range = {}, Location = {}, Diagnostic = {}, Method = {}, TextDocument = {}, }































































































lsp.error_code = {
   InternalError = -32603,
   InvalidParams = -32602,
   InvalidRequest = -32600,
   MethodNotFound = -32601,
   ParseError = -32700,
   ServerNotInitialized = -32002,
   UnknownErrorCode = -32001,
   serverErrorEnd = -32000,
   serverErrorStart = -32099,

   RequestCancelled = -32800,
}

lsp.severity = {
   Error = 1,
   Warning = 2,
   Information = 3,
   Hint = 4,
}

function lsp.position(y, x)
   return {
      character = x,
      line = y,
   }
end

return lsp