
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
      line: integer
      character: integer
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
         "textDocument/didOpen"
         "textDocument/didChange"
         "textDocument/didSave"
         "textDocument/didClose"

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

return lsp

