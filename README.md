# WIP and Currently (Very) Unstable
This is very much a work in progress. Work is being done in the Teal compiler itself to make development of this easier and the cli is undergoing changes as well to help with the project management tools that a language server expects to have (such as being able to properly load `tlconfig.lua`).

Development of this could require an experimental branch of Teal itself, the cli, or some other tool that may not yet exist. Check out the Teal gitter if you would like to contribute

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

And just runs a simple type check with no configuration options

# Setup

### NeoVim 0.5

Install the [lspconfig plugin](https://github.com/neovim/nvim-lspconfig) and put the following in your `init.vim` or `init.lua`
```lua
local lspconfig = require("lspconfig")
local configs = require("lspconfig/configs") -- Make sure this is a slash (as theres some metamagic happening behind the scenes)
if not lspconfig.teal then
   configs.teal = {
      default_config = {
         cmd = {
            "teal-language-server",
            -- "logging=on", use this to enable logging in /tmp/teal-language-server.log
         },
         filetypes = { "teal" };
         root_dir = lspconfig.util.root_pattern("tlconfig.lua", ".git"),
         settings = {};
      },
   }
end
lspconfig.teal.setup{}

```
