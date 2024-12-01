rockspec_format = "3.0"

package = "teal-language-server"
version = "0.1.0-1"

source = {
   url = "git+https://github.com/teal-language/teal-language-server.git",
   branch = "main"
}

description = {
   summary = "A language server for the Teal language",
   detailed = "A language server for the Teal language",
   homepage = "https://github.com/teal-language/teal-language-server",
   license = "MIT"
}

dependencies = {
   "luafilesystem",
   "tl",
   "lua-cjson",
   "argparse",
   "inspect",
   "luv",
   "lusc_luv >= 4.0",
   "ltreesitter-ts==0.0.1",
   -- install script works locally for me and installs via LuaRocks via hererocks without this line.
   -- trying to work with the CI/CD pipeline, hopefully this is all that's needed
   "luarocks-build-tree-sitter-cli==0.0.2", 
   "tree-sitter-cli==0.24.4",
   "tree-sitter-teal",
}

test_dependencies = { "busted~>2" }

test = {
   type = "busted",
   flags = {"-m", "gen/?.lua"},
}

build = {
   type = "builtin",
   modules = {
      ["teal_language_server.args_parser"] = "gen/teal_language_server/args_parser.lua",
      ["teal_language_server.asserts"] = "gen/teal_language_server/asserts.lua",
      ["teal_language_server.class"] = "gen/teal_language_server/class.lua",
      ["teal_language_server.constants"] = "gen/teal_language_server/constants.lua",
      ["teal_language_server.document"] = "gen/teal_language_server/document.lua",
      ["teal_language_server.document_manager"] = "gen/teal_language_server/document_manager.lua",
      ["teal_language_server.env_updater"] = "gen/teal_language_server/env_updater.lua",
      ["teal_language_server.lsp"] = "gen/teal_language_server/lsp.lua",
      ["teal_language_server.lsp_events_manager"] = "gen/teal_language_server/lsp_events_manager.lua",
      ["teal_language_server.lsp_formatter"] = "gen/teal_language_server/lsp_formatter.lua",
      ["teal_language_server.lsp_reader_writer"] = "gen/teal_language_server/lsp_reader_writer.lua",
      ["teal_language_server.main"] = "gen/teal_language_server/main.lua",
      ["teal_language_server.misc_handlers"] = "gen/teal_language_server/misc_handlers.lua",
      ["teal_language_server.path"] = "gen/teal_language_server/path.lua",
      ["teal_language_server.server_state"] = "gen/teal_language_server/server_state.lua",
      ["teal_language_server.stdin_reader"] = "gen/teal_language_server/stdin_reader.lua",
      ["teal_language_server.teal_project_config"] = "gen/teal_language_server/teal_project_config.lua",
      ["teal_language_server.trace_entry"] = "gen/teal_language_server/trace_entry.lua",
      ["teal_language_server.trace_stream"] = "gen/teal_language_server/trace_stream.lua",
      ["teal_language_server.tracing"] = "gen/teal_language_server/tracing.lua",
      ["teal_language_server.uri"] = "gen/teal_language_server/uri.lua",
      ["teal_language_server.util"] = "gen/teal_language_server/util.lua",
   },
   install = {
     bin = {
       ['teal-language-server'] = 'bin/teal-language-server'
     }
   }
}
