#!/bin/bash
set -e
cd "$(dirname "$0")/.."
luarocks_tree/bin/tlcheck src
echo "Linting complete."
