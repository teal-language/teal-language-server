#!/usr/bin/env bash

# yeah, this is a bit of a hack by utilizing hererocks and reconfigring it to be portable but it works!

set -e

python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install hererocks

hererocks -l "@v5.4.7" -r "@v3.11.1" tls

source tls/bin/activate
luarocks make

# TODO: see if we can just make this a build dependency?
luarocks remove --force tree-sitter-cli

rm -f ./tls/bin/activate* ./tls/bin/get_deactivated_path.lua
rm -f ./tls/bin/json2lua ./tls/bin/lua2json
rm -f ./tls/bin/luarocks ./tls/bin/luarocks-admin ./tls/bin/tl
rm -rf ./tls/include

tls_dir="$(pwd)/tls/"
sed -i '' -e '2i\
cd "$(dirname "$0")"' ./tls/bin/teal-language-server
sed -i '' -e "s*$tls_dir*../*g" ./tls/bin/teal-language-server

teal-language-server --help
