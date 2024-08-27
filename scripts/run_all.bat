@echo off
setlocal enabledelayedexpansion

call %~dp0generate_lua.bat
if %errorlevel% neq 0 exit /b %errorlevel%
call %~dp0lint_teal.bat
if %errorlevel% neq 0 exit /b %errorlevel%

REM We run setup_local_luarocks again here even though it is already run in generate_lua.bat
REM so that tea-leaves is deployed to luarocks tree
call %~dp0setup_local_luarocks.bat
if %errorlevel% neq 0 exit /b %errorlevel%
