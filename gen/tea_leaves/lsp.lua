




local lsp = {Message = {ResponseError = {}, }, Position = {}, Range = {}, Location = {}, Diagnostic = {}, Method = {}, TextDocument = {}, TextDocumentContentChangeEvent = {}, CompletionContext = {}, }

























































































































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

lsp.sync_kind = {
   None = 0,
   Full = 1,
   Incremental = 2,
}

lsp.completion_trigger_kind = {
   Invoked = 1,
   TriggerCharacter = 2,
   TriggerForIncompleteCompletions = 3,
}

function lsp.position(y, x)
   return {
      character = x,
      line = y,
   }
end

return lsp
