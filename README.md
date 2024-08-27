
# Teal Language Server

A language server for the [Teal language](https://github.com/teal-language/tl)

[![test](https://github.com/teal-language/teal-language-server/actions/workflows/test.yml/badge.svg)](https://github.com/teal-language/teal-language-server/actions/workflows/test.yml)

# Installation

### From luarocks

* `luarocks install teal-language-server`
* `teal-language-server`

Tested on Windows, Linux and MacOS

### From source

* Clone repo
* From repo root: 
  * `scripts/setup_local_luarocks`
  * `./lua_modules/bin/teal-language-server`

# Features

* Go to definition (`textDocument/definition`)
* Linting (`textDocument/publishDiagnostics`)
* Intellisense (`textDocument/completion`)
* Hover (`textDocument/hover`)

# Editor Setup

### Neovim

Install the [lspconfig plugin](https://github.com/neovim/nvim-lspconfig) and put the following in your `init.vim` or `init.lua`

```lua
local lspconfig = require("lspconfig")

lspconfig.teal_language_server.setup {}
```

# Usage

```
teal-language-server [--verbose=true] [--log-mode=none|by_proj_path|by_date]
```

Note:

* All args are optional
* By default, logging is 'none' which disables logging completely
* When logging is set to by_proj_path or by_date, the log is output to `[User Home Directory]/.cache/teal-language-server`

