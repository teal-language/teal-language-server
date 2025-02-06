#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
rm -rf ./gen
mkdir ./gen
mkdir ./gen/teal_language_server
luarocks_tree/bin/tl gen src/teal_language_server/args_parser.tl -o gen/teal_language_server/args_parser.lua
luarocks_tree/bin/tl gen src/teal_language_server/asserts.tl -o gen/teal_language_server/asserts.lua
cp src/teal_language_server/class.lua gen/teal_language_server/class.lua
luarocks_tree/bin/tl gen src/teal_language_server/constants.tl -o gen/teal_language_server/constants.lua
luarocks_tree/bin/tl gen src/teal_language_server/document.tl -o gen/teal_language_server/document.lua
luarocks_tree/bin/tl gen src/teal_language_server/document_manager.tl -o gen/teal_language_server/document_manager.lua
luarocks_tree/bin/tl gen src/teal_language_server/env_updater.tl -o gen/teal_language_server/env_updater.lua
luarocks_tree/bin/tl gen src/teal_language_server/lsp.tl -o gen/teal_language_server/lsp.lua
luarocks_tree/bin/tl gen src/teal_language_server/lsp_events_manager.tl -o gen/teal_language_server/lsp_events_manager.lua
luarocks_tree/bin/tl gen src/teal_language_server/lsp_formatter.tl -o gen/teal_language_server/lsp_formatter.lua
luarocks_tree/bin/tl gen src/teal_language_server/lsp_reader_writer.tl -o gen/teal_language_server/lsp_reader_writer.lua
luarocks_tree/bin/tl gen src/teal_language_server/main.tl -o gen/teal_language_server/main.lua
luarocks_tree/bin/tl gen src/teal_language_server/misc_handlers.tl -o gen/teal_language_server/misc_handlers.lua
luarocks_tree/bin/tl gen src/teal_language_server/path.tl -o gen/teal_language_server/path.lua
luarocks_tree/bin/tl gen src/teal_language_server/server_state.tl -o gen/teal_language_server/server_state.lua
luarocks_tree/bin/tl gen src/teal_language_server/stdin_reader.tl -o gen/teal_language_server/stdin_reader.lua
luarocks_tree/bin/tl gen src/teal_language_server/teal_project_config.tl -o gen/teal_language_server/teal_project_config.lua
luarocks_tree/bin/tl gen src/teal_language_server/trace_entry.tl -o gen/teal_language_server/trace_entry.lua
luarocks_tree/bin/tl gen src/teal_language_server/trace_stream.tl -o gen/teal_language_server/trace_stream.lua
luarocks_tree/bin/tl gen src/teal_language_server/tracing.tl -o gen/teal_language_server/tracing.lua
luarocks_tree/bin/tl gen src/teal_language_server/tracing_util.tl -o gen/teal_language_server/tracing_util.lua
luarocks_tree/bin/tl gen src/teal_language_server/uri.tl -o gen/teal_language_server/uri.lua
luarocks_tree/bin/tl gen src/teal_language_server/util.tl -o gen/teal_language_server/util.lua
