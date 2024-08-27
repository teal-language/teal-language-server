@echo off
setlocal enabledelayedexpansion
call %~dp0setup_local_luarocks.bat
cd %~dp0\..
rmdir /s /q gen
mkdir gen
mkdir gen\tea_leaves
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\args_parser.tl -o %~dp0\..\gen\tea_leaves\args_parser.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\asserts.tl -o %~dp0\..\gen\tea_leaves\asserts.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\constants.tl -o %~dp0\..\gen\tea_leaves\constants.lua
copy src\tea_leaves\class.lua gen\tea_leaves\class.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\document.tl -o %~dp0\..\gen\tea_leaves\document.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\document_manager.tl -o %~dp0\..\gen\tea_leaves\document_manager.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\env_updater.tl -o %~dp0\..\gen\tea_leaves\env_updater.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\lsp.tl -o %~dp0\..\gen\tea_leaves\lsp.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\lsp_events_manager.tl -o %~dp0\..\gen\tea_leaves\lsp_events_manager.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\lsp_reader_writer.tl -o %~dp0\..\gen\tea_leaves\lsp_reader_writer.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\main.tl -o %~dp0\..\gen\tea_leaves\main.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\misc_handlers.tl -o %~dp0\..\gen\tea_leaves\misc_handlers.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\path.tl -o %~dp0\..\gen\tea_leaves\path.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\server_state.tl -o %~dp0\..\gen\tea_leaves\server_state.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\stdin_reader.tl -o %~dp0\..\gen\tea_leaves\stdin_reader.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\teal_project_config.tl -o %~dp0\..\gen\tea_leaves\teal_project_config.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\trace_entry.tl -o %~dp0\..\gen\tea_leaves\trace_entry.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\trace_stream.tl -o %~dp0\..\gen\tea_leaves\trace_stream.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\tracing.tl -o %~dp0\..\gen\tea_leaves\tracing.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\uri.tl -o %~dp0\..\gen\tea_leaves\uri.lua
call luarocks\bin\tl.bat gen %~dp0\..\src\tea_leaves\util.tl -o %~dp0\..\gen\tea_leaves\util.lua
