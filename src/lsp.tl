
-- Type describing the actual protocol
-- most of these are adapted from the typescript types the spec gives at
-- https://microsoft.github.io/language-server-protocol/specifications/specification-current/

local record lsp

   enum ErrorName
      "InternalError"
      "InvalidParams"
      "InvalidRequest"
      "MethodNotFound"
      "ParseError"
      "ServerNotInitialized"
      "UnknownErrorCode"
      "serverErrorEnd"
      "serverErrorStart"

      "RequestCancelled"
   end

   error_code: {ErrorName:number}

   type JsonValue = string | number | boolean | JsonObject
   type JsonObject = {string:JsonValue}

   type integer = number
   type uinteger = number

   record Message
      id: integer | string

      -- Request/Notification
      method: string
      params: {string:any} -- should be {any} | {string:any}

      -- Response
      result: JsonValue
      record ResponseError
         code: integer
         message: string
         data: JsonValue
      end
      error: ResponseError
   end

   record Position
      -- Both of these are 0 based
      line: uinteger
      character: uinteger
   end

   record Range
      start: Position
      ["end"]: Position
   end

   record Location
      uri: string
      range: Range
   end

   enum Severity
      "Error"
      "Warning"
      "Information"
      "Hint"
   end
   severity: {Severity:integer}

   record Diagnostic
      range: Range
      severity: integer
      message: string
   end

   record Method
      enum Name
         "initialize"
         "initialized"
         "textDocument/didOpen"
         "textDocument/didChange"
         "textDocument/didSave"
         "textDocument/didClose"
         "textDocument/hover"

         "textDocument/publishDiagnostics"
      end

      type Params = {number|string:JsonValue} -- should be JsonObject | {JsonValue}
      type Method = function(Params, number)
   end

   record TextDocument
      uri: string
      version: integer
      text: string
      languageId: string
   end

   enum TextDocumentSyncKind
      "None"
      "Full"
      "Incremental"
   end
   sync_kind: {TextDocumentSyncKind:integer}

   record TextDocumentContentChangeEvent
      range: Range
      text: string
   end
end

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

function lsp.position(y: lsp.uinteger, x: lsp.uinteger): lsp.Position
   return {
      character = x,
      line = y,
   }
end

return lsp
