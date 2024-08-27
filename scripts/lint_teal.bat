@echo off
setlocal enabledelayedexpansion
REM Require this is called manually make output more clear
REM call %~dp0setup_local_luarocks.bat
cd %~dp0\..
call luarocks\bin\tlcheck.bat src
echo Linting complete
endlocal

