#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
rm -rf ./gen
mkdir ./gen
mkdir ./gen/tea_leaves
luarocks_tree/bin/tl gen src/tea_leaves/args_parser.tl -o gen/tea_leaves/args_parser.lua
luarocks_tree/bin/tl gen src/tea_leaves/asserts.tl -o gen/tea_leaves/asserts.lua
cp src/tea_leaves/class.lua gen/tea_leaves/class.lua
luarocks_tree/bin/tl gen src/tea_leaves/constants.tl -o gen/tea_leaves/constants.lua
luarocks_tree/bin/tl gen src/tea_leaves/document.tl -o gen/tea_leaves/document.lua
luarocks_tree/bin/tl gen src/tea_leaves/document_manager.tl -o gen/tea_leaves/document_manager.lua
luarocks_tree/bin/tl gen src/tea_leaves/env_updater.tl -o gen/tea_leaves/env_updater.lua
luarocks_tree/bin/tl gen src/tea_leaves/lsp.tl -o gen/tea_leaves/lsp.lua
luarocks_tree/bin/tl gen src/tea_leaves/lsp_events_manager.tl -o gen/tea_leaves/lsp_events_manager.lua
luarocks_tree/bin/tl gen src/tea_leaves/lsp_reader_writer.tl -o gen/tea_leaves/lsp_reader_writer.lua
luarocks_tree/bin/tl gen src/tea_leaves/main.tl -o gen/tea_leaves/main.lua
luarocks_tree/bin/tl gen src/tea_leaves/misc_handlers.tl -o gen/tea_leaves/misc_handlers.lua
luarocks_tree/bin/tl gen src/tea_leaves/path.tl -o gen/tea_leaves/path.lua
luarocks_tree/bin/tl gen src/tea_leaves/server_state.tl -o gen/tea_leaves/server_state.lua
luarocks_tree/bin/tl gen src/tea_leaves/stdin_reader.tl -o gen/tea_leaves/stdin_reader.lua
luarocks_tree/bin/tl gen src/tea_leaves/teal_project_config.tl -o gen/tea_leaves/teal_project_config.lua
luarocks_tree/bin/tl gen src/tea_leaves/trace_entry.tl -o gen/tea_leaves/trace_entry.lua
luarocks_tree/bin/tl gen src/tea_leaves/trace_stream.tl -o gen/tea_leaves/trace_stream.lua
luarocks_tree/bin/tl gen src/tea_leaves/tracing.tl -o gen/tea_leaves/tracing.lua
luarocks_tree/bin/tl gen src/tea_leaves/uri.tl -o gen/tea_leaves/uri.lua
luarocks_tree/bin/tl gen src/tea_leaves/util.tl -o gen/tea_leaves/util.lua
