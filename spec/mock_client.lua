
-- The most minimal lsp client implementation for testing

local json = require("dkjson")

local client = {
   textDocument = {}
}

local function TODO()
   error("TODO: Implement me!", 2)
end

function client.initialize()
   TODO()
end

function client.initialized()
   TODO()
end

function client.textDocument.didOpen()
   TODO()
end

function client.textDocument.didClose()
   TODO()
end

function client.textDocument.didSave(text)
   TODO()
end

function client.textDocument.hover()
   TODO()
end

return client

