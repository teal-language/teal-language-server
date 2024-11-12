
-- Type describing the actual protocol
-- most of these are adapted from the typescript types the spec gives at
-- https://microsoft.github.io/language-server-protocol/specifications/specification-current/

local tl <const> = require("tl")

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

   error_code: {ErrorName:integer}

   type JsonValue = string | number | boolean | JsonObject -- should also have {JsonValue}
   type JsonObject = {string:JsonValue}

   type uinteger = integer

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
         "textDocument/definition"
         "textDocument/publishDiagnostics"
         "textDocument/completion"
         "textDocument/signatureHelp"
         "shutdown"
      end

      type Params = {integer|string:JsonValue} -- should be JsonObject | {JsonValue}
      type Method = function(Params, integer)
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

   enum CompletionTriggerKind
      "Invoked"
      "TriggerCharacter"
      "TriggerForIncompleteCompletions"
   end
   completion_trigger_kind: {CompletionTriggerKind:integer}

   enum CompletionItemKind
      "Text"
      "Method"
      "Function"
      "Constructor"
      "Field"
      "Variable"
      "Class"
      "Interface"
      "Module"
      "Property"
      "Unit"
      "Value"
      "Enum"
      "Keyword"
      "Snippet"
      "Color"
      "File"
      "Reference"
      "Folder"
      "EnumMember"
      "Constant"
      "Struct"
      "Event"
      "Operator"
      "TypeParameter"
   end
   completion_item_kind: {CompletionItemKind:integer}
   typecodes_to_kind: {integer:integer}

   record CompletionContext
      triggerKind: integer
      triggerCharacter: string
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

lsp.completion_trigger_kind = {
   Invoked = 1,
   TriggerCharacter = 2,
   TriggerForIncompleteCompletions = 3,
}

lsp.completion_item_kind = {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
}

-- maybe could be moved to a different file or something.
-- it's one of the few that does a tl mapping to something outside of teal.
lsp.typecodes_to_kind = {
   -- Lua types
   [tl.typecodes.NIL]           = lsp.completion_item_kind.Variable,
   [tl.typecodes.NUMBER]        = lsp.completion_item_kind.Variable,
   [tl.typecodes.BOOLEAN]       = lsp.completion_item_kind.Variable,
   [tl.typecodes.STRING]        = lsp.completion_item_kind.Variable,
   [tl.typecodes.TABLE]         = lsp.completion_item_kind.Struct,
   [tl.typecodes.FUNCTION]      = lsp.completion_item_kind.Function,
   [tl.typecodes.USERDATA]      = lsp.completion_item_kind.Variable,
   [tl.typecodes.THREAD]        = lsp.completion_item_kind.Variable,
   -- -- Teal types
   [tl.typecodes.INTEGER]       = lsp.completion_item_kind.Variable,
   [tl.typecodes.ENUM]          = lsp.completion_item_kind.Enum,
   [tl.typecodes.ARRAY]         = lsp.completion_item_kind.Struct,
   [tl.typecodes.RECORD]        = lsp.completion_item_kind.Reference,
   [tl.typecodes.MAP]           = lsp.completion_item_kind.Struct,
   [tl.typecodes.TUPLE]         = lsp.completion_item_kind.Struct,
   [tl.typecodes.INTERFACE]     = lsp.completion_item_kind.Interface ,
   [tl.typecodes.SELF]          = lsp.completion_item_kind.Struct,
   [tl.typecodes.POLY]          = lsp.completion_item_kind.Function,
   [tl.typecodes.UNION]         = lsp.completion_item_kind.TypeParameter,
   -- -- Indirect types
   [tl.typecodes.NOMINAL]       = lsp.completion_item_kind.Variable,
   [tl.typecodes.TYPE_VARIABLE] = lsp.completion_item_kind.Reference,
   -- -- Special types
   [tl.typecodes.ANY]           = lsp.completion_item_kind.Variable,
   [tl.typecodes.UNKNOWN]       = lsp.completion_item_kind.Variable,
   [tl.typecodes.INVALID]       = lsp.completion_item_kind.Text,
}

function lsp.position(y: lsp.uinteger, x: lsp.uinteger): lsp.Position
   return {
      character = x,
      line = y,
   }
end

return lsp

