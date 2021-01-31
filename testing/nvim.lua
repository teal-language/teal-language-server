
-- For neovim users, just :luafile nvim.lua
-- It will attach the server to the current buffer

local lspconfig = require("lspconfig")
local client_id = vim.lsp.start_client{
   cmd = { "teal-language-server" },
   root_dir = lspconfig.util.root_pattern("tlconfig.lua"),
   handlers = vim.lsp.handlers,
}

vim.lsp.buf_attach_client(0, client_id)

