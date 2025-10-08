# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Teal Language Server, providing LSP support for the [Teal language](https://github.com/teal-language/tl). Teal is a typed dialect of Lua. The project is written in Teal (`.tl` files) and compiled to Lua for distribution via LuaRocks.

## Development Setup

Initial setup (required once):
```bash
scripts/setup_local_luarocks.sh  # or .bat on Windows
```

This creates a local LuaRocks tree in `luarocks_tree/` and installs all dependencies including the Teal compiler (`tl`), tree-sitter parsers, and testing framework.

## Build System

The project uses a two-stage build process:

1. **Teal → Lua compilation**: Source `.tl` files in `src/` are compiled to `.lua` files in `gen/`
2. **LuaRocks packaging**: The generated Lua files are packaged according to the rockspec

### Key Commands

**Build (compile Teal to Lua):**
```bash
scripts/generate_lua.sh  # or .bat on Windows
```

**Lint Teal source code:**
```bash
scripts/lint_teal.sh     # or .bat on Windows
```

**Run tests:**
```bash
scripts/run_tests.sh     # uses busted test framework
```

**Run development version:**
```bash
scripts/run_dev_tls.sh   # compile, install, and run with latest changes
```

## Architecture

### Core Components

- **`main.tl`**: Entry point, initializes logging and starts the LSP server
- **`lsp.tl`**: Core LSP message handling and dispatch
- **`lsp_events_manager.tl`**: Manages LSP event lifecycle and handlers
- **`document_manager.tl`**: Tracks open documents and their state
- **`server_state.tl`**: Maintains server configuration and workspace state
- **`env_updater.tl`**: Handles Teal environment and type checking integration

### LSP Features

The server implements:
- `textDocument/definition` (Go to definition)
- `textDocument/publishDiagnostics` (Linting/error reporting)  
- `textDocument/completion` (Intellisense)
- `textDocument/hover` (Symbol information)

### Directory Structure

- `src/teal_language_server/`: Main Teal source files
- `types/`: Teal type definitions for external libraries
- `gen/`: Generated Lua files (build artifact)
- `luarocks_tree/`: Local LuaRocks installation
- `scripts/`: Build and development scripts
- `spec/`: Test files (busted framework)

### Configuration

- `tlconfig.lua`: Teal compiler configuration (source_dir, build_dir, include_dir)
- `teal-language-server-*.rockspec`: LuaRocks package specification

## Development Workflow

### Testing Your Changes

The proper development cycle is:

1. **Edit** `.tl` files in `src/`
2. **Compile** Teal to Lua: `scripts/generate_lua.sh`
3. **Install** to LuaRocks tree: `luarocks make --tree=luarocks_tree`
4. **Test** using `luarocks_tree/bin/teal-language-server`

Or use the convenience script that does all steps:
```bash
scripts/run_dev_tls.sh [arguments...]
```

**Important:** The `gen/` directory contains your compiled Lua files, but the language server needs dependencies from the LuaRocks tree. Simply running `lua` from `gen/` won't work - you must install via `luarocks make` to sync your changes with the dependency-aware LuaRocks environment.

### Unit Testing

Tests use the busted framework and are run with:
```bash
scripts/run_tests.sh
# or directly: luarocks test --tree=luarocks_tree
```

Test files are located in `spec/` and the rockspec configures busted to load modules from `gen/?.lua`.

## Binary Distribution

The project creates standalone binaries using `scripts/create_binary.sh` for cross-platform distribution, particularly useful for Windows where LuaRocks installation can be challenging.