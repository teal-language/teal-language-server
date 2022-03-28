#!/bin/bash
set -e
cd `dirname $BASH_SOURCE`/..
luarocks init
./luarocks install luafilesystem
./luarocks install cyan
./luarocks install dkjson
