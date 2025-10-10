#!/bin/bash
set -e

# Navigate to the root of the repo
cd "$(dirname "$0")/.."

# Set the local LuaRocks path
LUAROCKS_TREE="$(pwd)/luarocks_tree"

echo "Compiling Teal files to Lua..."
scripts/generate_lua.sh

echo "Installing to LuaRocks tree..."
luarocks make --tree="$LUAROCKS_TREE"

echo "Running teal-language-server with latest changes..."
"$LUAROCKS_TREE/bin/teal-language-server" "$@"