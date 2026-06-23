
local args_parser = { CommandLineArgs = {} }














function args_parser.parse_args()
   local argparse = require("argparse")
   local parser = argparse("teal-language-server", "Teal Language Server")

   parser:option("-V --verbose"):
   description("Deprecated! Will just set -D TRACE")

   parser:option("-d --debug"):
   description("Set the log level - mostly for debugging issues with tested (default: 'WARNING')"):
   choices({ "TRACE", "DEBUG", "INFO", "WARNING" }):
   default("WARNING")

   parser:option("-L --log-mode", "Specify approach to logging.  By default it is none which means no logging.  by_date names the file according to date.  by_proj_path names file according to the teal project path"):
   choices({ "none", "by_date", "by_proj_path" })

   parser:flag("-C --coverage", "Enable luacov code coverage tracking (luacov must be installed; use 'luarocks test' or install it manually)"):hidden(true)

   local raw_args = parser:parse()

   local args = {
      verbose = raw_args["verbose"],
      debug = raw_args["debug"],
      log_mode = raw_args["log_mode"] or "none",
      coverage = raw_args["coverage"],
   }

   return args
end

return args_parser
