rockspec_format = "3.0"
package = "teal-language-server"
version = "dev-1"
source = {
   url = "git+https://git@github.com/teal-language/teal-language-server.git"
}
description = {
   summary = "A language server for the Teal language",
   detailed = "A language server for the Teal language. Experimental at best",
   homepage = "https://github.com/teal-language/teal-language-server",
   license = "MIT",
   issues_url = "https://github.com/teal-language/cyan/issues",
}
dependencies = {
   "dkjson",
   "luafilesystem",
   "cyan",
}
build = {
   type = "builtin",
   modules = {
      ["tealls.document"] = "build/tealls/document.lua",
      ["tealls.handlers"] = "build/tealls/handlers.lua",
      ["tealls.init"] = "build/tealls/init.lua",
      ["tealls.lsp"] = "build/tealls/lsp.lua",
      ["tealls.methods"] = "build/tealls/methods.lua",
      ["tealls.rpc"] = "build/tealls/rpc.lua",
      ["tealls.server"] = "build/tealls/server.lua",
      ["tealls.uri"] = "build/tealls/uri.lua",
      ["tealls.util"] = "build/tealls/util.lua",
   },
   install = {
      lua = {
         ["tealls.document"] = "src/document.tl",
         ["tealls.handlers"] = "src/handlers.tl",
         ["tealls.init"] = "src/init.tl",
         ["tealls.lsp"] = "src/lsp.tl",
         ["tealls.methods"] = "src/methods.tl",
         ["tealls.rpc"] = "src/rpc.tl",
         ["tealls.server"] = "src/server.tl",
         ["tealls.uri"] = "src/uri.tl",
         ["tealls.util"] = "src/util.tl",
      },
      bin = {
         "bin/teal-language-server"
      }
   }
}
