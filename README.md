
# Tea Leaves

A language server for the [Teal language](https://github.com/teal-language/tl)

[![test](https://github.com/svermeulen/tea-leaves/actions/workflows/test.yml/badge.svg)](https://github.com/svermeulen/tea-leaves/actions/workflows/test.yml)

# Installation

### From luarocks

* `luarocks install tea-leaves`
* `tea-leaves`

Tested on Windows, Linux and MacOS

### From source

* Clone repo
* From repo root: 
  * `scripts/setup_local_luarocks`
  * `./lua_modules/bin/tea-leaves`

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

lspconfig.tea_leaves.setup {}
```

# Usage

```
tea-leaves [--verbose=true] [--log-mode=none|by_proj_path|by_date]
```

Note:

* All args are optional
* By default, logging is 'none' which disables logging completely
* When logging is set to by_proj_path or by_date, the log is output to `[User Home Directory]/.cache/tea-leaves`

