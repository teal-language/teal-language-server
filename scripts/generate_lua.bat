@echo off
setlocal enabledelayedexpansion
call %~dp0setup_local_luarocks.bat
cd %~dp0\..
rmdir /s /q gen
mkdir gen
mkdir gen\teal_language_server
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\args_parser.tl -o %~dp0\..\gen\teal_language_server\args_parser.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\asserts.tl -o %~dp0\..\gen\teal_language_server\asserts.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\constants.tl -o %~dp0\..\gen\teal_language_server\constants.lua
copy src\teal_language_server\class.lua gen\teal_language_server\class.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\document.tl -o %~dp0\..\gen\teal_language_server\document.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\document_manager.tl -o %~dp0\..\gen\teal_language_server\document_manager.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\env_updater.tl -o %~dp0\..\gen\teal_language_server\env_updater.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\lsp.tl -o %~dp0\..\gen\teal_language_server\lsp.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\lsp_events_manager.tl -o %~dp0\..\gen\teal_language_server\lsp_events_manager.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\lsp_reader_writer.tl -o %~dp0\..\gen\teal_language_server\lsp_reader_writer.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\main.tl -o %~dp0\..\gen\teal_language_server\main.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\misc_handlers.tl -o %~dp0\..\gen\teal_language_server\misc_handlers.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\path.tl -o %~dp0\..\gen\teal_language_server\path.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\server_state.tl -o %~dp0\..\gen\teal_language_server\server_state.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\stdin_reader.tl -o %~dp0\..\gen\teal_language_server\stdin_reader.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\teal_project_config.tl -o %~dp0\..\gen\teal_language_server\teal_project_config.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\trace_entry.tl -o %~dp0\..\gen\teal_language_server\trace_entry.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\trace_stream.tl -o %~dp0\..\gen\teal_language_server\trace_stream.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\tracing.tl -o %~dp0\..\gen\teal_language_server\tracing.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\uri.tl -o %~dp0\..\gen\teal_language_server\uri.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\teal_language_server\util.tl -o %~dp0\..\gen\teal_language_server\util.lua
