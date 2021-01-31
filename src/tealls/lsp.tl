
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

   type integer = number
   record Message
      id: integer | string

      -- Request/Notification
      method: string
      params: {string:any} -- should be {any} | {string:any}

      -- Response
      result: string | number | boolean | table
      record ResponseError
         code: integer
         message: string
         data: string | number | boolean | table
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

      type Params = {number|string:any}
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

