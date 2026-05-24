#!/bin/bash
set -e
cd "$(dirname "$0")/.."
luarocks_tree/bin/cyan build
echo "Linting complete."
