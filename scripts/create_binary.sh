#!/usr/bin/env bash

# yeah, this is kinda hacky and abusing hererocks, but it works!

set -e

# python3 -m pip install hererocks
hererocks -l "@v5.4.7" -r "@v3.11.1" tls

source tls/bin/activate
luarocks install teal-language-server
rm ./tls/bin/activate* ./tls/bin/get_deactivated_path.lua
rm ./tls/bin/tree-sitter ./tls/bin/json2lua ./tls/bin/lua2json
rm ./tls/bin/luarocks ./tls/bin/luarocks-admin ./tls/bin/tl

tls_dir="$(pwd)/tls/"
sed -i '' -e '2i\
cd "$(dirname "$0")"' ./tls/bin/teal-language-server
sed -i '' -e "s*$tls_dir*../*g" ./tls/bin/teal-language-server

teal-language-server --help
