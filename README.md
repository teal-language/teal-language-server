# WIP and Currently (Very) Unstable
This is very much a work in progress. Work is being done in the Teal compiler itself to make development of this easier and the cli is undergoing changes as well to help with the project management tools that a language server expects to have (such as being able to properly load `tlconfig.lua`).

Check out the Teal gitter if you would like to contribute

[![Join the chat at https://gitter.im/dotnet/coreclr](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/teal-language/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

```
luarocks install --dev teal-language-server
```

# teal-language-server

Currently the server only implements:
 - `textDocument/didOpen`
 - `textDocument/didSave`
 - `textDocument/didClose`
 - `textDocument/hover`

And just runs a simple type check

# Setup

If you can get this working with your editor, please open an issue/pr to add it here!

### Neovim 0.7

Install the [lspconfig plugin](https://github.com/neovim/nvim-lspconfig) and put the following in your `init.vim` or `init.lua`
```lua
local lspconfig = require("lspconfig")

lspconfig.teal_ls.setup {}
```
