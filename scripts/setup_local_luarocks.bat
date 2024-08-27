@echo off
setlocal enabledelayedexpansion

rem Navigate to the root of the repo
cd %~dp0\..

rem Check if the local luarocks tree is already initialized
if not exist "luarocks" (
    echo Initializing local LuaRocks tree...
    luarocks init --tree=./luarocks
) else (
    echo Local LuaRocks tree already exists.
)

rem Set the local LuaRocks path
set "LUAROCKS_TREE=%~dp0\..\luarocks"

rem Install project dependencies from the rockspec
echo Installing project dependencies...
call luarocks make --tree=!LUAROCKS_TREE!

echo Installing tlcheck for linting...
call luarocks install tlcheck --tree=!LUAROCKS_TREE!

rem Confirm installations
echo Installed LuaRocks packages:
call luarocks list --tree=!LUAROCKS_TREE!

endlocal

