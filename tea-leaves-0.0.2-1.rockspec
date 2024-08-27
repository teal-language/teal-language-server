rockspec_format = "3.0"
package = "tea-leaves"
version = "0.0.2-1"
source = {
   url = "git+https://github.com/svermeulen/tea-leaves.git",
   branch = "main"
}
description = {
   summary = "A language server for the Teal language",
   detailed = "A language server for the Teal language",
   homepage = "https://github.com/svermeulen/tea-leaves",
   license = "MIT"
}
dependencies = {
   "luafilesystem",
   "tl",
   "dkjson",
   "argparse",
   "inspect",
   "luv",
   "lusc_luv >= 4.0",
}
build = {
   type = "builtin",
   modules = {
      ["tea_leaves.args_parser"] = "gen/tea_leaves/args_parser.lua",
      ["tea_leaves.asserts"] = "gen/tea_leaves/asserts.lua",
      ["tea_leaves.class"] = "gen/tea_leaves/class.lua",
      ["tea_leaves.constants"] = "gen/tea_leaves/constants.lua",
      ["tea_leaves.document"] = "gen/tea_leaves/document.lua",
      ["tea_leaves.document_manager"] = "gen/tea_leaves/document_manager.lua",
      ["tea_leaves.env_updater"] = "gen/tea_leaves/env_updater.lua",
      ["tea_leaves.lsp"] = "gen/tea_leaves/lsp.lua",
      ["tea_leaves.lsp_events_manager"] = "gen/tea_leaves/lsp_events_manager.lua",
      ["tea_leaves.lsp_reader_writer"] = "gen/tea_leaves/lsp_reader_writer.lua",
      ["tea_leaves.main"] = "gen/tea_leaves/main.lua",
      ["tea_leaves.misc_handlers"] = "gen/tea_leaves/misc_handlers.lua",
      ["tea_leaves.path"] = "gen/tea_leaves/path.lua",
      ["tea_leaves.server_state"] = "gen/tea_leaves/server_state.lua",
      ["tea_leaves.stdin_reader"] = "gen/tea_leaves/stdin_reader.lua",
      ["tea_leaves.teal_project_config"] = "gen/tea_leaves/teal_project_config.lua",
      ["tea_leaves.trace_entry"] = "gen/tea_leaves/trace_entry.lua",
      ["tea_leaves.trace_stream"] = "gen/tea_leaves/trace_stream.lua",
      ["tea_leaves.tracing"] = "gen/tea_leaves/tracing.lua",
      ["tea_leaves.uri"] = "gen/tea_leaves/uri.lua",
      ["tea_leaves.util"] = "gen/tea_leaves/util.lua",
   },
   install = {
     bin = {
       ['tea-leaves'] = 'bin/tea-leaves'
     }
   }
}
