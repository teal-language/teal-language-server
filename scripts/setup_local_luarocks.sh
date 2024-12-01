#!/bin/bash
set -e

# Navigate to the root of the repo
cd "$(dirname "$0")/.."

# Set the local LuaRocks path
LUAROCKS_TREE="$(pwd)/luarocks_tree"

# setup local LuaRocks
luarocks init --tree="$LUAROCKS_TREE"
PATH="$LUAROCKS_TREE/bin":"$PATH"
export PATH

# Install project dependencies from the rockspec
echo "Installing project dependencies..."
luarocks make --tree="$LUAROCKS_TREE"

echo "Installing tlcheck for linting..."
luarocks install tlcheck --tree="$LUAROCKS_TREE"

# Confirm installations
echo "Installed LuaRocks packages:"
luarocks list --tree="$LUAROCKS_TREE"
