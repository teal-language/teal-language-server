[![test](https://github.com/teal-language/teal-language-server/actions/workflows/test.yml/badge.svg)](https://github.com/teal-language/teal-language-server/actions/workflows/test.yml)

# Teal Language Server

A language server for the [Teal language](https://github.com/teal-language/tl)


## Installation

### From luarocks

* `luarocks install teal-language-server`
* `teal-language-server` should now be installed!

Tested on Linux and macOS. Currently a bit of a struggle to install via LuaRocks on Windows. We recommend using the binaries from the release on Windows.

### From GitHub Release Binaries
We provide binaries for Windows and macOS on our [GitHub Release](https://github.com/teal-language/teal-language-server/releases) page. You should be able to download and extract the the latest version from there.

### From source

* Clone repo
* From repo root: 
  * `scripts/setup_local_luarocks`
  * `./lua_modules/bin/teal-language-server`

## Features

* Go to definition (`textDocument/definition`)
* Linting (`textDocument/publishDiagnostics`)
* Intellisense (`textDocument/completion`)
* Hover (`textDocument/hover`)

## Editor Setup

### Neovim

Install the [lspconfig plugin](https://github.com/neovim/nvim-lspconfig) and put the following in your `init.vim` or `init.lua`

```lua
local lspconfig = require("lspconfig")

-- as long as teal-language-server is in your PATH this should work
lspconfig.teal_ls.setup {}

-- if it's not in your path, you can specify a cmd as per the following:
-- lspconfig.teal_ls.setup({cmd = { 'C:\\opt\\tls-windows\\bin\\teal-language-server.bat' },})
```

## Usage

```
teal-language-server [--verbose=true] [--log-mode=none|by_proj_path|by_date]
```

Note:

* All args are optional
* By default, logging is 'none' which disables logging completely
* When logging is set to `by_proj_path` or `by_date`, the log is output to `[User Home Directory]/.cache/teal-language-server`

