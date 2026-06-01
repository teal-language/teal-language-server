#!/bin/bash
set -e

# Navigate to the root of the repo
cd "$(dirname "$0")/.."

# Set the local LuaRocks path
LUAROCKS_TREE="$(pwd)/luarocks_tree"

echo "Install"
luarocks make --tree="$LUAROCKS_TREE"

# add teal-language-server to path for luarocks test
PATH="$LUAROCKS_TREE/bin":"$PATH"
export PATH

# Run unit tests
echo "Run LuaRocks tests:"
luarocks install tested --tree="$LUAROCKS_TREE"
luarocks test --tree="$LUAROCKS_TREE"
