#!/bin/bash
set -e

# Navigate to the root of the repo
cd "$(dirname "$0")/.."

luarocks init --tree=./luarocks_tree

# Set the local LuaRocks path
LUAROCKS_TREE="$(pwd)/luarocks_tree"

# Install project dependencies from the rockspec
echo "Installing project dependencies..."
luarocks make --tree="$LUAROCKS_TREE"

echo "Installing tlcheck for linting..."
luarocks install tlcheck --tree="$LUAROCKS_TREE"

# Confirm installations
echo "Installed LuaRocks packages:"
luarocks list --tree="$LUAROCKS_TREE"
