#!/bin/bash
set -e
cd `dirname $BASH_SOURCE`/..
./lua_modules/bin/cyan build
./luarocks make
