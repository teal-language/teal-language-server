#!/bin/bash
set -e

# Navigate to the root of the repo
cd "$(dirname "$0")/.."

# Set the local LuaRocks path
LUAROCKS_TREE="$(pwd)/luarocks_tree"

echo "Install"
luarocks make --tree="$LUAROCKS_TREE"

# Run unit tests
echo "Run LuaRocks tests:"
luarocks test --tree="$LUAROCKS_TREE"
