
--[[
   For neovim users, just :luafile nvim.lua
   It will attach the server to the current buffer
   ex, if you are in the current dir (testing/) just run

   $ nvim test.tl "+luafile nvim.lua"
]]

local client_id = vim.lsp.start_client{
   cmd = { "../bin/teal-language-server" },
   root_dir = vim.fn.getcwd(),
   handlers = vim.lsp.handlers,
}

print("started server with id: ", client_id)
vim.lsp.buf_attach_client(0, client_id)

