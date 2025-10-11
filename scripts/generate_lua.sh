#!/bin/bash
set -ex
cd `dirname $BASH_SOURCE`/..
rm -rf ./gen
mkdir ./gen
mkdir ./gen/teal_language_server

cp src/teal_language_server/class.lua gen/teal_language_server/class.lua

tl gen src/teal_language_server/args_parser.tl -o gen/teal_language_server/args_parser.lua
tl gen src/teal_language_server/asserts.tl -o gen/teal_language_server/asserts.lua
tl gen src/teal_language_server/build_handler.tl -o gen/teal_language_server/build_handler.lua
tl gen src/teal_language_server/constants.tl -o gen/teal_language_server/constants.lua
tl gen src/teal_language_server/debug_flags.tl -o gen/teal_language_server/debug_flags.lua
tl gen src/teal_language_server/diagnostics_helper.tl -o gen/teal_language_server/diagnostics_helper.lua
tl gen src/teal_language_server/diagnostics_publisher.tl -o gen/teal_language_server/diagnostics_publisher.lua
tl gen src/teal_language_server/env_factory.tl -o gen/teal_language_server/env_factory.lua
tl gen src/teal_language_server/files_util.tl -o gen/teal_language_server/files_util.lua
tl gen src/teal_language_server/i_disposable.tl -o gen/teal_language_server/i_disposable.lua
tl gen src/teal_language_server/lsp.tl -o gen/teal_language_server/lsp.lua
tl gen src/teal_language_server/lsp_events_manager.tl -o gen/teal_language_server/lsp_events_manager.lua
tl gen src/teal_language_server/lsp_formatter.tl -o gen/teal_language_server/lsp_formatter.lua
tl gen src/teal_language_server/lsp_reader_writer.tl -o gen/teal_language_server/lsp_reader_writer.lua
tl gen src/teal_language_server/main.tl -o gen/teal_language_server/main.lua
tl gen src/teal_language_server/misc_handlers.tl -o gen/teal_language_server/misc_handlers.lua
tl gen src/teal_language_server/module_info.tl -o gen/teal_language_server/module_info.lua
tl gen src/teal_language_server/module_info_manager.tl -o gen/teal_language_server/module_info_manager.lua
tl gen src/teal_language_server/open_document.tl -o gen/teal_language_server/open_document.lua
tl gen src/teal_language_server/open_document_registry.tl -o gen/teal_language_server/open_document_registry.lua
tl gen src/teal_language_server/path_util.tl -o gen/teal_language_server/path_util.lua
tl gen src/teal_language_server/server_state.tl -o gen/teal_language_server/server_state.lua
tl gen src/teal_language_server/stdin_reader.tl -o gen/teal_language_server/stdin_reader.lua
tl gen src/teal_language_server/teal_project_config.tl -o gen/teal_language_server/teal_project_config.lua
tl gen src/teal_language_server/trace_entry.tl -o gen/teal_language_server/trace_entry.lua
tl gen src/teal_language_server/trace_stream.tl -o gen/teal_language_server/trace_stream.lua
tl gen src/teal_language_server/tracing.tl -o gen/teal_language_server/tracing.lua
tl gen src/teal_language_server/tracing_util.tl -o gen/teal_language_server/tracing_util.lua
tl gen src/teal_language_server/uri.tl -o gen/teal_language_server/uri.lua
tl gen src/teal_language_server/util.tl -o gen/teal_language_server/util.lua
