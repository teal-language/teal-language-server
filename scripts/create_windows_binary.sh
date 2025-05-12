#!/usr/bin/env bash

set -e

# make this our "main" folder
mv luarocks teal-language-server

# install lua
mv .lua/bin/lua.exe teal-language-server/bin/
mv .lua/bin/lua54.dll teal-language-server/bin/

# clean out bin
cd teal-language-server/bin
rm -f json2lua.bat lua2json.bat tl.bat

# modify teal-language-server.bat
# a bit hacky, but should preseve some version numbers
sed -i 's*set "LUAROCKS_SYSCONFDIR=C:\\Program Files\\luarocks"*cd /D "%~dp0"*g' teal-language-server.bat
sed -i 's*D:\\a\\teal-language-server\\teal-language-server\\.lua\\bin\\lua.exe*.\\lua.exe*g' teal-language-server.bat
sed -i 's*D:\\\\a\\\\teal-language-server\\\\teal-language-server\\\\luarocks*..*g' teal-language-server.bat
sed -i 's*D:\\a\\teal-language-server\\teal-language-server\\luarocks*..*g' teal-language-server.bat
