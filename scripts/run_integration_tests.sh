#!/bin/bash
set -e

cd "$(dirname "$0")/.."

LUAROCKS_TREE="$(pwd)/tls"

if [ ! -d "$LUAROCKS_TREE" ]; then
    echo "Error: tls/ tree not found. Please ensure the tls/ directory exists." >&2
    exit 1
fi

echo "Installing tested into tls tree (if not already present)..."
"$LUAROCKS_TREE/bin/luarocks" install tested --tree="$LUAROCKS_TREE" 2>/dev/null || true

echo "Running integration tests:"
LUA_PATH="./?.lua;$LUAROCKS_TREE/share/lua/5.4/?.lua;$LUAROCKS_TREE/share/lua/5.4/?/init.lua;;" \
LUA_CPATH="$LUAROCKS_TREE/lib/lua/5.4/?.so;;" \
    "$LUAROCKS_TREE/bin/tested" -n 0 tests/
