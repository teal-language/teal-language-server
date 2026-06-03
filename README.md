[![test](https://github.com/teal-language/teal-language-server/actions/workflows/platform-test.yaml/badge.svg)](https://github.com/teal-language/teal-language-server/actions/workflows/platform-test.yaml)

# Teal Language Server

A language server for the [Teal language](https://github.com/teal-language/tl)

## Features

* Go to definition (`textDocument/definition`)
* Linting (`textDocument/publishDiagnostics`)
* Intellisense (`textDocument/completion`)
* Hover (`textDocument/hover`)

## Installation

### From GitHub Release Binaries (Windows)
We provide binaries for Windows on our [GitHub Release](https://github.com/teal-language/teal-language-server/releases) page. You should be able to download and extract the the latest version from there.

### via LuaRocks

If using LuaRocks, be sure to have LuaRocks binary path available on your PATH!

On macOS and Linux, the standard `luarocks install` should work:

- `luarocks install teal-language-server`

On Windows:
- If using Visual Studio, please be sure to have the C++ build tools, and note that the default cmake generator (`Visual Studio 14 2015`) does not work. We recommend using `NMake Makefiles`
    ```bash
    luarocks config cmake_generator "NMake Makefiles"
    luarocks install teal-language-server
    ```

- If using mingw, additional `CFLAGS` also need to be set so some of the upstream dependencies will compile:
    ```bash
    set CFLAGS=-O2 -Wno-int-conversion -Wno-incompatible-pointer-types
    luarocks config cmake_generator "MinGW Makefiles"
    luarocks install teal-language-server
    ```
    If using Powershell, set the CFLAGS with: `$env:CFLAGS = "-O2 -Wno-int-conversion -Wno-incompatible-pointer-types"`


### From source

1. Clone repo
2. Run a `luarocks make` - this should work however your LuaRocks is setup!
    - If using Windows, please set the `cmake_generator` and `CFLAGS` as described in the installation section!

## Editor Setup

### Neovim

Install the [lspconfig plugin](https://github.com/neovim/nvim-lspconfig) and put the following in your `init.vim` or `init.lua`

```lua
local lspconfig = require("lspconfig")

-- as long as teal-language-server is in your PATH this should work
lspconfig.teal_ls.setup {}

-- if it's not in your path, you can specify where teal-languag-server is by setting cmd. For example on Windows:
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

## Licences
Alongside packages defined in the rockspec, teal-language-server includes the source of the following:

- [tree-sitter-teal](https://github.com/euclidianAce/tree-sitter-teal) - MIT
  - Bundling directly makes install more reliable, as tree-sitter-cli does not need to be setup for the install to work
